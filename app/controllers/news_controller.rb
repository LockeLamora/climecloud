require 'wombat'
require 'uri'
require "open-uri"
require 'action_view'
require 'net/http'
require 'crack'

class NewsController < ApplicationController
    include ActionView::Helpers::SanitizeHelper
    def news
        get_articles
        render :list
    end

    def article
        get_articles
        @article_url = @articles[params[:article].to_i]["url"]
        @article = scrape_article(@article_url).html_safe
        puts @articles
        render :article
    end

    private

    def resolve_article_rules(url)
        if url.include?'cnbc.com'
            return ".PageBuilder-article p"
        elsif ['bbc.com', 'bbc.co.uk', 'ap.com',].any? { |provider| url.include? provider }
            return "p"
        else
            return "p"
        end
    end

    def scrape_article(url)
        res = Net::HTTP.get_response(URI(url))
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
        
        params = {
             :hl => 'en-GB',
             :gl => @loc.upcase,
             :ceid => 'GB:en'
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
end
