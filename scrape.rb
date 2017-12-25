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
    sleep(3)
    charset = nil

    html = open(url) do |f|
      charset = f.charset # 文字種別を取得
      f.read
    end

    # htmlをパース(解析)してオブジェクトを生成
    Nokogiri::HTML.parse(html, nil, charset)
  end

  def TicketCampFreewordUrl(url, freeword)
    doc = HtmlDoc(url)

    names = doc.xpath("//form[contains(@action, 'search')]").map { |form|
      name = form.xpath("//input[@type='text']/@name")
      '' if name == nil
      action = form[:action]
      uri = URI.parse(url)
      uri.merge(action).to_s + "?#{name}=#{freeword}"
    }.compact.reject(&:empty?)

    URI.encode(names[0])
  end

  def FreewordResults(search_url)
    doc = HtmlDoc(search_url)

    section = doc.css('section.module-list-performer')
    section.css('div.module-list-performer-row').map {|result|
      clearfix = result.css('div.clearfix')

      next if clearfix == nil

      a = clearfix.css('a')[0]
      text = a.inner_html
      link = a[:href]
      url = "https:#{link}"
      {"#{text}" => "#{url}"}
    }.compact.reject(&:empty?)
  end

  def DetailUrls(url)
    p "url = #{url}"
    doc = HtmlDoc(url)

    doc.css('li.unavailable').map { |unavailable|
      watch = unavailable.css('li.watch')[0]

      next if watch == nil

      ticket_status = watch.css('span.text-muted')[0].inner_html

      next unless ticket_status == '取引中'

      img = unavailable.css('li.img')[0]
      img.css('a')[0][:href]
    }.compact.reject(&:empty?)
  end

  def tdInnerHtml(td, inners)
    inners.map{ |inner|
      html = td.css(inner)

      next if html == nil
      html.inner_html
    }
  end

  def DetailScrape(url)
    doc = HtmlDoc(url)

    ticket_info = doc.css('div.module-ticket-info')[0]
    ticket_info.css('tr').map { |tr|
      th = tr.css('th')[0]
      td = tr.css('td')[0]

      return '' if td == nil

      a = td.css('a')
      return td.inner_html if a == nil
      a.inner_html
    }
  end

  def NextPage(doc)
    pagination = doc.css('div.pagination')[0]
    next_page = pagination.css('li.next')[0]

    return '' if next_page == nil

    href = next_page.css('a')[0][:href]
    'https:' + href
  end

  freewordUrl = TicketCampFreewordUrl(url, ARGV[0])
  results = FreewordResults(freewordUrl)

  p "以下から番号を選択(カンマ(,)区切りで複数可)"
  results.each_with_index do |item, index|
    p "#{index} : #{item.keys[0]}"
  end

  inputs = STDIN.gets
  indexes = inputs.split(',').map(&:to_i).uniq

  p "indexes = #{indexes}"

  urls_bundle = results.map.with_index { |item, index|
    next unless indexes.include?(index)
    DetailUrls(item.values[0])
  }.flatten.compact.reject(&:empty?)

  p "#{urls_bundle.size}個の「取引中」のチケット詳細が見つかりました。詳細を抽出しますか。y/n"

  ipt = STDIN.gets

  if ipt == "y\n"
    csv = CSV.open('scrape.csv','w')

    scrapes = urls_bundle.map.with_index { |url, index|
      print "\r#{index+1}/#{urls_bundle.size} complete"
      csv.puts DetailScrape(url)
    }

    csv.close
  end

end
