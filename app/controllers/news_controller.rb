require 'wombat'

class NewsController < ApplicationController
    def news
        get_articles
        render :list
    end

    def article
        get_articles
        article_url = @articles[params[:article].to_i]["url"]
        @article = scrape_article(article_url)["text"]
        render :article
    end


    private

    def scrape_article(url)
        Wombat.crawl do
            base_url url
            text css:"p"
        end
    end

    def get_articles
        resolve_location
        uri = build_news_uri
        get_news_from_api(uri)
    end

    def build_news_uri
        uri = URI("https://saurav.tech/NewsAPI/top-headlines/category/general/#{@loc}.json")
        uri
    end

    def get_news_from_api(uri)
        res = Net::HTTP.get_response(uri)
        body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        @articles = body["articles"]
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
