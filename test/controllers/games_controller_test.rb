# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

class GamesControllerTest < ActionDispatch::IntegrationTest
  # The books ship with the app: no saved location is required and nothing external is
  # ever requested, which WebMock's disable_net_connect! enforces across the suite.

  test 'lists the bundled books' do
    get '/games'

    assert_response :success
    assert_match 'Consider the Consequences!', @response.body
    assert_match 'Treasure Hunt', @response.body
  end

  test 'offers to begin a book not yet started' do
    get '/games/treasure-hunt'

    assert_response :success
    assert_match I18n.t('games.begin'), @response.body
    assert_no_match(/#{I18n.t('games.restart')}/, @response.body)
  end

  test 'offers continue and restart once a bookmark is saved' do
    get '/games/treasure-hunt/5'
    get '/games/treasure-hunt'

    assert_response :success
    assert_match I18n.t('common.continue'), @response.body
    assert_match I18n.t('games.restart'), @response.body
    assert_match '/games/treasure-hunt/5', @response.body
  end

  test 'ignores a bookmark that no longer names a section' do
    cookies['CYOA'] = { 'treasure-hunt' => 'gone' }.to_json

    get '/games/treasure-hunt'

    assert_match I18n.t('games.begin'), @response.body
  end

  test 'a bookmark at the very start still reads as a fresh book' do
    get '/games/treasure-hunt/0'
    get '/games/treasure-hunt'

    assert_match I18n.t('games.begin'), @response.body
  end

  test 'remembers the last section read, one entry per book' do
    get '/games/treasure-hunt/7'
    get '/games/consider-the-consequences/H-1'

    saved = JSON.parse(cookies['CYOA'])
    assert_equal '7', saved['treasure-hunt']
    assert_equal 'H-1', saved['consider-the-consequences']
  end

  test 'shows a section with its text and numbered choices' do
    get '/games/treasure-hunt/1'

    assert_response :success
    assert_match 'two tall yew hedges', @response.body
    assert_match '/games/treasure-hunt/5', @response.body
    assert_match '/games/treasure-hunt/7', @response.body
    assert_match '/gamebooks/treasure-hunt/p1.png', @response.body
  end

  test 'a consequence without a destination is text rather than a link' do
    get '/games/treasure-hunt/2'

    assert_match 'they give up and go home', @response.body
    assert_no_match(/<a[^>]*>[^<]*give up and go home/, @response.body)
  end

  test 'an ending offers to start the book again' do
    ending = Gamebooks.find('consider-the-consequences')['sections']
                      .find { |_id, section| section['choices'].empty? }
                      .first

    get "/games/consider-the-consequences/#{ending}"

    assert_match I18n.t('games.the_end'), @response.body
    assert_match '/games/consider-the-consequences/start', @response.body
  end

  test 'sends an unknown book back to the shelf and an unknown section to its book' do
    get '/games/unknown'
    assert_redirected_to '/games'

    get '/games/treasure-hunt/999'
    assert_redirected_to '/games/treasure-hunt'
  end

  test 'a garbled cookie is treated as no progress at all' do
    cookies['CYOA'] = 'not json'

    get '/games/treasure-hunt'
    assert_response :success
    assert_match I18n.t('games.begin'), @response.body

    get '/games/treasure-hunt/5'
    assert_equal({ 'treasure-hunt' => '5' }, JSON.parse(cookies['CYOA']))
  end

  test 'every choice in every bundled book leads to a section that exists' do
    Gamebooks.all.each do |book|
      book['sections'].each do |id, section|
        section['choices'].each do |choice|
          next unless choice['to']

          assert book['sections'].key?(choice['to']),
                 "#{book['id']} #{id} points at missing section #{choice['to']}"
        end
      end
      assert book['sections'].key?(book['start']),
             "#{book['id']} start #{book['start']} is missing"
    end
  end
end
