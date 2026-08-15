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
    assert_match 'fill="#FF8100"', @response.body
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

  # A newline in the label starts a fresh line, which is how a table travels as one glyph:
  # each row a line, the columns aligned by the monospace itself.
  test 'a newline in the label starts a fresh line' do
    get phosphor_url, params: { t: "TIME TEMP\n21:00 17°", s: 'crt-green' }

    texts = @response.body.scan(%r{<text[^>]*>([^<]*)</text>}).flatten

    assert_equal ['TIME TEMP', '21:00 17°'], texts
  end

  test 'is cacheable, since the same label in the same hue is the same picture' do
    get phosphor_url, params: { t: '0 Back to menu' }, headers: { 'HTTP_COOKIE' => 'theme=plasma' }

    assert_match 'public', @response.headers['Cache-Control']
  end

  # The URL names the hue so a cache holding last month's image can never hand a reader who
  # changed style the old style's pixels: a different hue is a different URL.
  test 'the hue in the URL outranks the cookie' do
    get phosphor_url, params: { t: 'anything', s: 'crt-green' },
                      headers: { 'HTTP_COOKIE' => 'theme=crt-amber' }

    assert_match 'fill="#52FF8F"', @response.body
    assert_no_match(/FF8100/, @response.body)
  end

  test 'headings and one-button forms are glyphed alongside the links' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-green;lat=51.5;city=Testville' }

    assert_match %r{<h2><img src="/phosphor\?s=crt-green&amp;t=Climecloud"}, @response.body
    assert_match %r{<b><img src="/phosphor\?s=crt-green&amp;t=Dumbphone\+utilities\+dashboard"},
                 @response.body
  end

  # Prose keeps its case — a whole article in capitals is a wall — while labels and
  # headings stay in the capitals the terminals these styles borrow from set theirs in.
  test 'prose keeps its case where a label is set in capitals' do
    get phosphor_url, params: { t: 'The cat is a small carnivore.', c: '1', s: 'crt-amber' }

    assert_match 'The cat is a small', @response.body

    get phosphor_url, params: { t: 'The cat is a small carnivore.', s: 'crt-amber' }

    assert_match 'THE CAT IS A SMALL', @response.body
  end

  test 'an unrecognised theme falls back to the plain palette rather than erroring' do
    get phosphor_url, params: { t: 'anything' }, headers: { 'HTTP_COOKIE' => 'theme=bogus' }

    assert_response :success
    assert_match 'fill="#ffffff"', @response.body
  end

  test 'the menu links carry the glyphs on a phosphor style and plain text elsewhere' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber;lat=51.5;city=Testville' }

    # The theme rides in the URL: the image is cached for a year, and a key that does not
    # name the hue serves a reader who changes style the old style's pixels.
    assert_match %r{<a accesskey="1"[^>]*><img src="/phosphor\?s=crt-amber&amp;t=1\+Weather\+forecast"},
                 @response.body
    assert_match(/alt="1 Weather forecast"/, @response.body)

    get root_url, headers: { 'HTTP_COOKIE' => 'theme=nokia;lat=51.5;city=Testville' }

    assert_no_match(/phosphor\?t=/, @response.body)
    assert_match(/<a accesskey="1"[^>]*>1 Weather forecast/, @response.body)
  end
end
