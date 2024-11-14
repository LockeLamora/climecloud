require 'wombat'
require 'domainatrix'
require 'net/http'

module Scraper 

def self.scrape_article(url, useragent)
    res = Net::HTTP.get_response(URI(url), { 'user-agent' => @useragent })
    unless res.code.start_with?('2', '3')
        Rails.logger.warn("Cannot load page - response #{res.code} - url #{@article_url}")
        return 'Cannot load page'
    end

    rule = resolve_article_rules(url)

    begin
        Wombat.set_user_agent(useragent)
        out = Wombat.crawl do
            base_url url
            path '/'
            text({ css: rule }, :list)
        end
    rescue StandardError
        Rails.logger.warn("Cannot parse page - url #{url}")
        return 'Cannot parse page'
    end

    out['text'].join('<br /><br />')
end

private  

    def self.resolve_article_rules(url)
        parsedurl = Domainatrix.parse(url)
        domain = "#{parsedurl.domain}.#{parsedurl.public_suffix}"

        rules = {
            'cnbc.com' => '.PageBuilder-article p',
            'independent.co.uk' => '#main p',
            'cnn.com' => '.article__content p',
            'politicshome.com' => '.newsview p',
            'gov.uk' => '.news-article p',
            'itv.com' => '#main-content p',
            'newscientist.com' => '.ArticleContent p',
            'dailymail.co.uk' => "[itemprop='articleBody'] p",
            'indiatimes.com' => '.clearfix *',
            'politico.eu' => '.article__content p',
            'dailyrecord.co.uk' => '.article-body p',
            'foxnews.com' => '.article-body p',
            'iflscience.com' => '.article-content p',
            'nytimes.com' => '.StoryBodyCompanionColumn p',
            'businessinsider.com' => '.content-lock-content p',
            'usatoday.com' => '.content-well p',
            'cbsnews.com' => '.content__body p',
            'nypost.com' => '.entry-content p',
            'ynetnews.com' => '.public-DraftEditor-content',
            'pbs.org' => '.body-text p'
        }
        rules.key?(domain) ? rules[domain] : 'p'
    end
end

