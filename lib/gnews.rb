require 'net/http'
require 'uri'

class Gnews 

def initialize(params = nil)
    resolve_location(params.delete(:country_code))
    resolve_language
    resolve_ceid
    @section = params.delete(:section)
    @useragent = params.delete(:useragent) || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)'\
     'Chrome/122.0.0.0 Safari/537.36'
end

def change_section(section)
    @section = section
end

def get_article(url)
    res = Net::HTTP.get_response(URI(url), { 'user-agent' => @useragent })
    while res.code.start_with?('3')
      res = Net::HTTP.get_response(URI(res.to_hash['location'][0]), { 'user-agent' => @useragent })
    end

    timestamp = get_timestamp(res.body)
    signature = get_signature(res.body)

    url.gsub!('https://news.google.com/rss/articles/', '')
    url.gsub!('?oc=5', '')
    url = rss_to_url(url, timestamp, signature)
end

def get_articles_from_api(search_query = nil)
    uri = build_news_uri(search_query)
    @res = Net::HTTP.get_response(uri)
    @res = Net::HTTP.get_response(URI.parse(@res['location'])) if @res.code.start_with?('3')
    body = @res.body if @res.is_a?(Net::HTTPSuccess)
    body = JSON.parse(Hash.from_xml(body).to_json)
    articles = body['rss']['channel']['item']
    title = if !@section.nil? && @section.upcase != 'HEADLINES'
               body['rss']['channel']['title']
             else
               'Headlines - Latest - Google News'
             end
    return articles, title         
  end

private

def resolve_location(country_code = 'us')
    supported = %w[gb us in fr au ru]
    @loc = if supported.include? country_code
                country_code
            else
                'us'
            end
    end

    def resolve_language
    locs = {
        'fr' => 'fr',
        'in' => 'hi',
        'us' => 'en-US',
        'gb' => 'en-GB',
        'au' => 'en-AU',
        'ru' => 'ru'
    }

    @language = locs[@loc]
    end

    def resolve_ceid
    c = @loc.upcase
    ceids = {
        'FR' => "#{c}:#{@language}",
        'IN' => "#{c}:#{@language}",
        'US' => "#{c}:en",
        'GB' => "#{c}:en",
        'AU' => "#{c}:en",
        'RU' => "#{c}:#{@language}"
    }

    @ceid = ceids[c]
    end

    def get_signature(html_source)
        match = html_source.match(/data-n-a-sg="([^"]+)"/)
        match ? match[1] : nil
      end
  
      def get_timestamp(html_source)
        match = html_source.match(/data-n-a-ts="([^"]+)"/)
        match ? match[1] : nil
      end

    def rss_to_url(url, timestamp, signature)
        uri = "https://news.google.com/_/DotsSplashUi/data/batchexecute"#?rpcids=Fbv4je"
        req = '[[["Fbv4je","[\"garturlreq\",[[\"en-GB\",\"GB\",[\"FINANCE_TOP_INDICES\",\"WEB_TEST_1_0_0\"],null,null,1,1,\"GB:en\",null,0,null,null,null,null,null,0,5],\"en-GB\",\"GB\",1,[2,4,8],1,1,\"691331303\",0,0,null,0],\"'+url+'\",'+timestamp+',\"'+signature+'\"]",null,"generic"]]]'
        res = Net::HTTP.post_form URI(uri), {"f.req" => req}
        url = URI.extract(res.body, ['http', 'https'])
        url[0]
    end  

    def build_news_uri(search_query = nil)
        URI('https://news.google.com/rss')
        params = {
          hl: @language,
          gl: @loc.upcase,
          ceid: @ceid
        }
        uri = nil
    
        if search_query
            uri = URI('https://news.google.com/rss/search')
            params[:q] = search_query
        elsif !@section.nil? && @section.upcase != 'HEADLINES'
          uri = URI("https://news.google.com/rss/headlines/section/topic/#{@section.upcase}")
        else
          uri = URI('https://news.google.com/rss')
        end
        uri.query = URI.encode_www_form(params)
        uri
    end
end