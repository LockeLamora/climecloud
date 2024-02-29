class NewsController < ApplicationController
    def news
        resolve_location
        uri = build_news_uri
        get_news_from_api(uri)
        render :list
    end

    private

    def build_news_uri
        uri = URI('https://saurav.tech/NewsAPI/top-headlines/category/general/gb.json')
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
