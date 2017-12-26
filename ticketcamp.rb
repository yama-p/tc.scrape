module TicketCamp
  extend self

  # URLにアクセスするためのライブラリの読み込み
  require 'open-uri'
  # Nokogiriライブラリの読み込み
  require 'nokogiri'
  # CSV
  require "csv"

  # スクレイピング先のURL
  url = 'https://ticketcamp.net/'

  def HtmlDoc(url)
    sleep(4)
    charset = nil

    html = open(url) do |f|
      charset = f.charset
      f.read
    end

    # htmlをパース(解析)してオブジェクトを生成
    Nokogiri::HTML.parse(html, nil, charset)
  end

  def TicketCampFreewordUrl(url, freeword)
    doc = HtmlDoc(url)
    uri = URI.parse(url)

    doc.xpath("//form[contains(@action, 'search')]")
      .map { |form| [form.xpath("//input[@type='text']/@name"), form[:action]] }
      .map { |items| items[0] == nil || items[1] == nil ? nil : items}
      .compact
      .map { |items| uri.merge(items[1]).to_s + "?#{items[0]}=#{freeword}"}
      .map { |name| URI.encode(name)}[0]
  end

  def FreewordResults(search_url)
    doc = HtmlDoc(search_url)

    doc.xpath("//section[@class='module-list-performer']")
      .map { |section| section.xpath("//div[@class='module-list-performer-row']") }
      .flatten
      .map { |result| result.css('div.clearfix') }
      .compact
      .map { |clearfix| clearfix.css('a')[0] }
      .compact
      .map { |a|
        text = a.inner_html
        link = a[:href]
        url = "https:#{link}"
        {"#{text}" => "#{url}"}
      }.reject(&:empty?)
  end

  def DetailUrls(url)
    doc = HtmlDoc(url)

    urls = DetailUrlsOnePage(doc)
    next_url = NextPage(doc)
    urls << DetailUrls(next_url) unless next_url.empty?

    urls.flatten
  end

  def DetailUrlsOnePage(doc)
    doc.css('li.unavailable').map { |unavailable|
      watch = unavailable.css('li.watch')[0]

      next if watch == nil

      ticket_status = watch.css('span.text-muted')[0].inner_html

      next unless ticket_status == '取引中'

      img = unavailable.css('li.img')[0]
      img.css('a')[0][:href]
    }.compact.reject(&:empty?)
  end

  def DetailHeadScrape(url)
    doc = HtmlDoc(url)

    ticket_info = doc.css('div.module-ticket-info')[0]
    ticket_info.css('tr').map { |tr|
      th = tr.css('th')[0]
      th == nil ? '' : th.inner_html
    }
  end

  def DetailScrape(url)
    doc = HtmlDoc(url)

    ticket_info = doc.css('div.module-ticket-info')[0]
    ticket_info.css('tr').map { |tr|
      td = tr.css('td')[0]

      next '' if td == nil

      tag = TagScrape(td)
      next tag unless tag.empty?

      next td.inner_html
    }.map { |v|
      v.gsub(/(\r\n|\r|\n|\f|\x20)/,"")
    }
  end

  def TagScrape(doc)
    atags = Tag(doc, 'a')
    spantags = Tag(doc, 'span')
    litags = Tag(doc, 'li')

    return atags[0] if atags.size > 0
    return spantags[0] if spantags.size > 0
    return litags[0] if litags.size > 0

    ''
  end

  def Tag(doc, tag_name)
    doc.css(tag_name).map { |t|
      tag = TagScrape(t)
      next tag unless tag.empty?
      t.inner_html
    }.compact.reject(&:empty?)
  end

  def NextPage(doc)
    pagination = doc.css('div.pagination')[0]
    return '' if pagination == nil

    next_page = pagination.css('li.next')[0]
    return '' if next_page == nil

    href = next_page.css('a')[0][:href]
    'https:' + href
  end

  freeword_url = TicketCampFreewordUrl(url, ARGV[0])
  results = FreewordResults(freeword_url)

  p "以下から番号を選択(カンマ(,)区切りで複数可)"
  results.each_with_index do |item, index|
    p "#{index} : #{item.keys[0]}"
  end

  inputs = STDIN.gets
  indexes = inputs.split(',').map(&:to_i).uniq

  p "選択番号：#{indexes}"

  urls_bundle = results.map.with_index { |item, index|
    next unless indexes.include?(index)
    DetailUrls(item.values[0])
  }.flatten.compact.reject(&:empty?)

  p "#{urls_bundle.size}個の「取引中」のチケット詳細が見つかりました。詳細を抽出しますか。y/n"

  ipt = STDIN.gets

  if ipt == "y\n"
    csv = CSV.open('scrape.csv','w')

    scrapes = urls_bundle.map.with_index { |url_text, index|
      if index == 0
        csv.puts DetailHeadScrape(url_text)
      end
      print "\r#{index+1}/#{urls_bundle.size} を抽出中"
      csv.puts DetailScrape(url_text)
    }

    csv.close
  end

  print "\n完了!!"

end
