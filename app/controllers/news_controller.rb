require 'wombat'
require 'uri'
require "open-uri"
require 'action_view'
require 'net/http'

class NewsController < ApplicationController
    include ActionView::Helpers::SanitizeHelper
    def news
        get_articles
        render :list
    end

    def article
        @article_url = params[:article]
        @article = scrape_article(@article_url).html_safe
        render :article
    end

    private

    def resolve_article_rules(url)
        if url.include?'cnbc.com'
            return ".PageBuilder-article p"
        elsif ['bbc.com', 'bbc.co.uk', 'ap.com',].any? { |provider| url.include? provider }
            return "p"
        elsif url.include? 'independend.co.uk'
            return "#main"    
        else
            return "p"
        end
    end

    def scrape_article(url)
        url.gsub!('https://news.google.com/rss/articles/','')
        url.gsub!('?oc=5','')
        url = Base64.decode64(url)
        url = URI.extract(url, /http(s)?|mailto/)[0]
        @article_url = url
        useragent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        res = Net::HTTP::get_response(URI(url), {'user-agent' => useragent})  
        return "Cannot load page" if !res.code.start_with?('2', '3')
        rule = resolve_article_rules(url)
        
        begin
            out = Wombat.crawl do
                base_url url
                path "/"
            
                text({css:rule}, :list)
            end
        rescue 
            return "Cannot load page"
        end
        
        out["text"].join("<br /><br />") 
    end

    def dosubs(html)
        html.gsub!( "‘", "'" )    
        html.gsub!( "’", "'" )  
        html.gsub!( "“", '"' )
        html.gsub!( "”", '"' )
        html.gsub!( "–", '-' )
        html
    end

    def get_articles
        resolve_location
        uri = build_news_uri
        get_news_from_api(uri)
    end

    def build_news_uri
        uri = URI("https://news.google.com/rss")
        lang = resolve_lang
        ceid = resolve_ceid(lang)
        params = {
             :hl => lang,
             :gl => @loc.upcase,
             :ceid => ceid
            }

        uri.query = URI.encode_www_form(params)
        uri
    end

    def get_news_from_api(uri)
        res = Net::HTTP.get_response(uri)
        body = res.body if res.is_a?(Net::HTTPSuccess)
        body = JSON.parse(Hash.from_xml(body).to_json)
        @articles = body["rss"]["channel"]["item"]
    end

    def resolve_location
        supported = %w(gb us in fr au ru)
        if supported.include?cookies["country_code"]
            @loc = cookies["country_code"]
        else
            @loc = 'us'
        end
    end

    def resolve_lang
        case cookies["country_code"]
        when 'fr'
            return 'fr'
        when 'in'
            return 'hi'   
        when 'us'
            return 'en-US'
        when 'gb'
            return 'en-GB'
        when 'au'
            return 'en-AU'
        when 'ru'
            return 'ru'          
        end     
    end

    def resolve_ceid(lang)
        c = cookies["country_code"].upcase
        case c
        when 'FR'
            return c + ':' + lang
        when 'IN'
            return c + ':' + lang   
        when 'US'
            return c + ':en' 
        when 'GB'
            return c + ':en'
        when 'AU'
            return c + ':en'
        when 'RU'
            return c + ':' + lang         
        end 
    end
end
