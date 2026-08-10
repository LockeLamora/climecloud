# frozen_string_literal: true

require 'test_helper'

class WikipediaControllerTest < ActionDispatch::IntegrationTest
  test 'offers a search box with nothing typed yet' do
    get '/wikipedia'

    assert_response :success
    assert_match 'Wikipedia', @response.body
    assert_match 'Search', @response.body
    assert_not_requested :get, /wikipedia\.org/
  end

  test 'lists the articles matching a search' do
    stub_search([
                  { 'title' => 'Test Subject', 'snippet' => 'A <span class="searchmatch">test</span> subject' },
                  { 'title' => 'Test Subject (album)', 'snippet' => 'An album' }
                ])

    get '/wikipedia', params: { query: 'test subject' }

    assert_response :success
    assert_match 'Test Subject', @response.body
    assert_match 'Test Subject (album)', @response.body
    # Highlight markup stripped, since it is no use on a small screen.
    assert_match 'A test subject', @response.body
    assert_no_match(/searchmatch/, @response.body)
  end

  test 'names itself to wikipedia so it is not throttled as unidentified' do
    stub_search([])

    get '/wikipedia', params: { query: 'anything' }

    assert_requested :get, /wikipedia\.org/ do |request|
      request.headers['User-Agent'].to_s.include?('climecloud')
    end
  end

  test 'says so plainly when a search matches nothing' do
    stub_search([])

    get '/wikipedia', params: { query: 'qwertyuiop' }

    assert_response :success
    assert_match 'Nothing found', @response.body
  end

  test 'shows the lead section of an article with a link to the rest' do
    stub_article('Test Subject', 'The lead section of the article.')

    get '/wikipedia_article', params: { title: 'Test Subject' }

    assert_response :success
    assert_match 'The lead section of the article.', @response.body
    assert_match 'Read the full article', @response.body
    # Asking for only the intro keeps the page small over 4G.
    assert_requested :get, /wikipedia\.org/ do |request|
      request.uri.query.include?('exintro=1')
    end
  end

  test 'asks for the whole article when the reader wants it' do
    stub_article('Test Subject', 'Every section of the article.')

    get '/wikipedia_article', params: { title: 'Test Subject', full: '1' }

    assert_response :success
    assert_match 'Every section of the article.', @response.body
    assert_no_match(/Read the full article/, @response.body)
    assert_requested :get, /wikipedia\.org/ do |request|
      !request.uri.query.include?('exintro')
    end
  end

  test 'reports rather than crashes when an article is missing' do
    stub_request(:get, /wikipedia\.org/)
      .to_return(status: 200, body: { 'query' => { 'pages' => {} } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    get '/wikipedia_article', params: { title: 'Nothing At All' }

    assert_response :success
    assert_match 'Could not find that article', @response.body
  end

  test 'says wikipedia is busy rather than blaming the search' do
    stub_request(:get, /wikipedia\.org/).to_return(status: 429, body: '')

    get '/wikipedia', params: { query: 'test subject' }

    assert_response :success
    assert_match 'Wikipedia is busy', @response.body
  end

  test 'reports rather than crashes when wikipedia is unreachable' do
    stub_request(:get, /wikipedia\.org/).to_return(status: 500, body: '')

    get '/wikipedia', params: { query: 'test subject' }

    assert_response :success
    assert_match 'Could not reach Wikipedia', @response.body
  end

  private

  def stub_search(results)
    stub_request(:get, /wikipedia\.org/)
      .to_return(status: 200,
                 body: { 'query' => { 'search' => results } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_article(title, extract)
    page = { '1' => { 'title' => title, 'extract' => extract } }

    stub_request(:get, /wikipedia\.org/)
      .to_return(status: 200,
                 body: { 'query' => { 'pages' => page } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end
end
