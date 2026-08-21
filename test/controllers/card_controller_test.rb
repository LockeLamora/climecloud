# frozen_string_literal: true

require 'test_helper'

# The playing-card pictures: suits as paths in the right colour, cacheable for a
# year, and nothing served for a code that is not a card.
class CardControllerTest < ActionDispatch::IntegrationTest
  test 'a heart is red, a club is black, and a ten spells itself out' do
    get '/card/4h'
    assert_response :success
    assert_equal 'image/svg+xml', @response.media_type
    assert_match 'fill="#C0182C"', @response.body
    assert_match '>4<', @response.body

    get '/card/4c'
    assert_match 'fill="#111111"', @response.body

    get '/card/Th'
    assert_match '>10<', @response.body
  end

  test 'the suits are drawn as paths, never as characters a rasteriser may lack' do
    %w[2h 2d 2s 2c].each do |code|
      get "/card/#{code}"
      assert_no_match(/[♥♦♣♠]/, @response.body, "#{code} leans on a suit glyph")
      assert_match(/<path|<circle/, @response.body)
    end
  end

  test 'the back is drawn and anything else is not a card' do
    get '/card/back'
    assert_response :success
    assert_match '#1E5AA8', @response.body

    get '/card/xx'
    assert_response :not_found

    get '/card/4h'
    assert_match 'public', @response.headers['Cache-Control'],
                 'the same card is the same picture for a year'
  end
end
