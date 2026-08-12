# frozen_string_literal: true

require 'domainatrix'

# Where the story sits on the sites that need telling. Kept apart from the scraper because
# it is a list of other people's markup rather than anything about fetching or reading a
# page, and it grows every time a publisher redesigns.
#
# Most sites need no entry: the scraper looks for the structured body first, then the
# containers an article usually sits in. These are the ones where neither works.
module ArticleRules
  DEFAULT = 'p'

  BY_DOMAIN = {
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
    'pbs.org' => '.body-text p',
    'telegraph.co.uk' => '.articleBodyText',
    'time.com' => '#article-body p'
  }.freeze

  def self.for(url)
    parsed = Domainatrix.parse(url)

    BY_DOMAIN.fetch("#{parsed.domain}.#{parsed.public_suffix}", DEFAULT)
  end
end
