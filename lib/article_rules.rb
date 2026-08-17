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
    # ITV writes its newsletter and podcast plugs inside the article body as paragraphs
    # wholly in <strong>, which no length or class filter catches; the story's own
    # paragraphs use none.
    'itv.com' => '#main-content p:not(:has(strong))',
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
    'time.com' => '#article-body p',
    'chinadaily.com.cn' => '#Content p',
    'gamesradar.com' => '#article-body p',
    'thenews.com.pk' => '.story-detail p',
    'videogameschronicle.com' => '#content_body p',
    'whatsonstage.com' => '.news-content p',
    'oceanographicmagazine.com' => '.user-content p',
    'marvel.com' => '.ContentBlock__Text p',
    'shropshire.gov.uk' => '.post .body p',
    'specificationonline.co.uk' => '.article--content p',
    'distilledpost.com' => '.w-richtext p',
    # The body class carries a build hash that changes on deploys; matched by its stem.
    'pistonheads.com' => '[class*="NewsArticleBody"] p',
    'timeout.com' => '#content p',
    # WordPress with Elementor: the story is the post-content widget, and the bare widget
    # class alone also matches the footer.
    'railadvent.co.uk' => '.elementor-widget-theme-post-content p',
    'todaysconveyancer.co.uk' => '.elementor-widget-theme-post-content p',
    '411mania.com' => '.content p',
    'chemanalyst.com' => '.blog-list-data p',
    'dlcompare.com' => '.news-body p',
    'doctors.net.uk' => '.news-story__body p',
    'thegrocer.co.uk' => '.storytext p',
    'helsinki.fi' => 'hy-paragraph-text p',
    'gpfans.com' => '.articlecontent_txt p',
    'insideci.co.uk' => '#Content p',
    'samsung.com' => '.text_cont p',
    # The post body is one div of text with no paragraph tags inside it.
    'techpowerup.com' => 'div.text'
  }.freeze

  def self.for(url)
    parsed = Domainatrix.parse(url)

    BY_DOMAIN.fetch("#{parsed.domain}.#{parsed.public_suffix}", DEFAULT)
  end
end
