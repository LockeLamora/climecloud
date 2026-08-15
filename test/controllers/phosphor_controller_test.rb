# frozen_string_literal: true

require 'test_helper'

# Text drawn as a phosphor screen. The glow cannot travel as CSS — a text-shadow reaches the
# handset as a filled band behind each text run, and gradients and alpha are disabled on
# Opera's servers — so it travels inside an SVG, which those servers rasterise into pixels.
class PhosphorControllerTest < ActionDispatch::IntegrationTest
  test 'draws the label as a glowing rastered screen in the chosen hue' do
    get phosphor_url, params: { t: '1 Weather forecast' },
                      headers: { 'HTTP_COOKIE' => 'theme=crt-amber' }

    assert_response :success
    assert_equal 'image/svg+xml', @response.media_type
    # The bloom is real blur, merged under the sharp text, and the raster is a pattern —
    # both composited on Opera's servers, not on the phone.
    assert_match 'feGaussianBlur', @response.body
    assert_match 'feMerge', @response.body
    assert_match '<pattern', @response.body
    assert_match 'fill="#FFB43C"', @response.body
    assert_match 'fill="#0C0803"', @response.body
    assert_match '1 WEATHER FORECAST', @response.body
  end

  test 'wraps a long label to the column instead of outgrowing the screen' do
    get phosphor_url, params: { t: 'Chancellor announces surprise change to national insurance' },
                      headers: { 'HTTP_COOKIE' => 'theme=crt-green' }

    width = @response.body[/width="(\d+)"/, 1].to_i

    assert_operator width, :<=, 220, 'an image wider than the screen costs the single column'
    assert_operator @response.body.scan('<text').length, :>, 1
  end

  # The label is whatever a page put in a link, so it goes through as text, never as markup.
  test 'escapes the label rather than lending it to the SVG' do
    get phosphor_url, params: { t: '<script>alert(1)</script>' },
                      headers: { 'HTTP_COOKIE' => 'theme=crt-green' }

    assert_response :success
    assert_no_match(/<script/i, @response.body)
    assert_match '&lt;SCRIPT&gt;', @response.body
  end

  test 'is cacheable, since the same label in the same hue is the same picture' do
    get phosphor_url, params: { t: '0 Back to menu' }, headers: { 'HTTP_COOKIE' => 'theme=plasma' }

    assert_match 'public', @response.headers['Cache-Control']
  end

  test 'an unrecognised theme falls back to the plain palette rather than erroring' do
    get phosphor_url, params: { t: 'anything' }, headers: { 'HTTP_COOKIE' => 'theme=bogus' }

    assert_response :success
    assert_match 'fill="#ffffff"', @response.body
  end

  test 'the menu links carry the glyphs on a phosphor style and plain text elsewhere' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber;lat=51.5;city=Testville' }

    assert_match %r{<a accesskey="1"[^>]*><img src="/phosphor\?t=1\+Weather\+forecast" [^>]*alt="1 Weather forecast"},
                 @response.body

    get root_url, headers: { 'HTTP_COOKIE' => 'theme=nokia;lat=51.5;city=Testville' }

    assert_no_match(/phosphor\?t=/, @response.body)
    assert_match(/<a accesskey="1"[^>]*>1 Weather forecast/, @response.body)
  end
end
