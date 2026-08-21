# frozen_string_literal: true

require 'test_helper'
require 'c64_glyph'
require 'teletext_glyph'

# Text drawn as an image: a phosphor screen for the phosphor styles, the machine's own
# character set for the C64 and teletext. The glow cannot travel as CSS — a text-shadow
# reaches the handset as a filled band behind each text run, and gradients and alpha are
# disabled on Opera's servers — and no font a page names ever reaches the device, so both
# travel inside an SVG, which those servers rasterise into pixels.
class GlyphControllerTest < ActionDispatch::IntegrationTest
  test 'draws the label as a glowing rastered screen in the chosen hue' do
    get glyph_url, params: { t: '1 Weather forecast' },
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
    get glyph_url, params: { t: 'Chancellor announces surprise change to national insurance' },
                   headers: { 'HTTP_COOKIE' => 'theme=crt-green' }

    width = @response.body[/width="(\d+)"/, 1].to_i

    assert_operator width, :<=, 220, 'an image wider than the screen costs the single column'
    assert_operator @response.body.scan('<text').length, :>, 1
  end

  # The label is whatever a page put in a link, so it goes through as text, never as markup.
  test 'escapes the label rather than lending it to the SVG' do
    get glyph_url, params: { t: '<script>alert(1)</script>' },
                   headers: { 'HTTP_COOKIE' => 'theme=crt-green' }

    assert_response :success
    assert_no_match(/<script/i, @response.body)
    assert_match '&lt;SCRIPT&gt;', @response.body
  end

  # A newline in the label starts a fresh line, which is how a table travels as one glyph:
  # each row a line, the columns aligned by the monospace itself.
  test 'a newline in the label starts a fresh line' do
    get glyph_url, params: { t: "TIME TEMP\n21:00 17°", s: 'crt-green' }

    texts = @response.body.scan(%r{<text[^>]*>([^<]*)</text>}).flatten

    assert_equal ['TIME TEMP', '21:00 17°'], texts
  end

  test 'is cacheable, since the same label in the same hue is the same picture' do
    get glyph_url, params: { t: '0 Back to menu' }, headers: { 'HTTP_COOKIE' => 'theme=plasma' }

    assert_match 'public', @response.headers['Cache-Control']
  end

  # The URL names the hue so a cache holding last month's image can never hand a reader who
  # changed style the old style's pixels: a different hue is a different URL.
  test 'the hue in the URL outranks the cookie' do
    get glyph_url, params: { t: 'anything', s: 'crt-green' },
                   headers: { 'HTTP_COOKIE' => 'theme=crt-amber' }

    assert_match 'fill="#52FF8F"', @response.body
    assert_no_match(/FF8100/, @response.body)
  end

  # The good and error roles take each theme's own values — see Themes::PALETTES —
  # on both renderers: the character-set styles and the phosphor screens alike. On a
  # screen that is already green, good comes out yellow rather than invisible.
  test 'the good and error roles take their colours from the theme palette' do
    get glyph_url, params: { t: 'Eat a meal', s: 'teletext', g: '1' }
    assert_match 'fill="#00FF00"', @response.body

    get glyph_url, params: { t: 'Needs the rope', s: 'teletext', r: '1' }
    assert_match 'fill="red"', @response.body

    get glyph_url, params: { t: 'Eat a meal', s: 'crt-green', g: '1' }
    assert_match 'fill="#EAFF52"', @response.body
  end

  test 'headings and one-button forms are glyphed alongside the links' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-green;lat=51.5;city=Testville' }

    assert_match %r{<h2><img src="/glyph\?e=1&amp;s=crt-green&amp;t=Climecloud"}, @response.body
    assert_match %r{<b><img src="/glyph\?e=1&amp;s=crt-green&amp;t=Dumbphone\+utilities\+dashboard"},
                 @response.body
  end

  # Prose keeps its case — a whole article in capitals is a wall — while labels and
  # headings stay in the capitals the terminals these styles borrow from set theirs in.
  test 'prose keeps its case where a label is set in capitals' do
    get glyph_url, params: { t: 'The cat is a small carnivore.', c: '1', s: 'crt-amber' }

    assert_match 'The cat is a small', @response.body

    get glyph_url, params: { t: 'The cat is a small carnivore.', s: 'crt-amber' }

    assert_match 'THE CAT IS A SMALL', @response.body
  end

  test 'an unrecognised theme falls back to the plain palette rather than erroring' do
    get glyph_url, params: { t: 'anything' }, headers: { 'HTTP_COOKIE' => 'theme=bogus' }

    assert_response :success
    assert_match 'fill="#ffffff"', @response.body
  end

  test 'the menu links carry the glyphs on a phosphor style and plain text elsewhere' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber;lat=51.5;city=Testville' }

    # The theme rides in the URL: the image is cached for a year, and a key that does not
    # name the hue serves a reader who changes style the old style's pixels.
    assert_match %r{<a accesskey="1"[^>]*><img src="/glyph\?l=1&amp;s=crt-amber&amp;t=1\+Weather\+forecast"},
                 @response.body
    assert_match(/alt="1 Weather forecast"/, @response.body)

    get root_url, headers: { 'HTTP_COOKIE' => 'theme=nokia;lat=51.5;city=Testville' }

    assert_no_match(/glyph\?t=/, @response.body)
    assert_match(/<a accesskey="1"[^>]*>1 Weather forecast/, @response.body)
  end

  # The C64's text travels the same way for a different reason: no font a page names ever
  # reaches the handset, so the machine's character set goes as its own 8x8 bitmaps, drawn
  # into the SVG as filled rectangles. No <text> at all — the shapes are the pixels — and
  # no background, so whatever the page painted behind the glyph shows through.
  test 'the c64 draws the label as its own character bitmaps' do
    get glyph_url, params: { t: '1 Weather forecast', s: 'c64' }

    assert_response :success
    assert_equal 'image/svg+xml', @response.media_type
    assert_no_match(/<text/, @response.body, 'device text would arrive in the device font')
    assert_no_match(/feGaussianBlur/, @response.body, 'the machine put flat squares on the glass')
    assert_match '<rect x=', @response.body
    assert_no_match(/<rect width="100%"/, @response.body, 'a baked background hides the page behind it')
  end

  # The machine wrote its links in a colour of its own — VIC-II white against the light
  # blue text — and the colour is baked into the image, so it has to be named in the URL
  # the cache is keyed by.
  test 'a c64 link glyph takes the link colour and a label the ink' do
    get glyph_url, params: { t: '4 News', s: 'c64', l: '1' }

    assert_match 'fill="#FFFFFF"', @response.body

    get glyph_url, params: { t: '4 News', s: 'c64' }

    assert_match 'fill="#8578CF"', @response.body
    assert_no_match(/fill="#FFFFFF"/, @response.body)
  end

  # Teletext travels as the SAA5050's 6x10 characters. Its headings are Ceefax yellow,
  # named in the URL like every baked colour, and drawn over the blue block the stylesheet
  # puts behind a heading — which is why the image has no background of its own.
  test 'teletext draws the label in its character set and headings in yellow' do
    get glyph_url, params: { t: '5 Wikipedia', s: 'teletext' }

    assert_response :success
    assert_no_match(/<text/, @response.body)
    assert_match '<rect x=', @response.body
    assert_match 'fill="#FFFFFF"', @response.body

    get glyph_url, params: { t: 'Hourly forecast', s: 'teletext', e: '1' }

    assert_match 'fill="#FFFF00"', @response.body
    assert_no_match(/<rect width="100%"/, @response.body, 'the heading block behind must show through')
  end

  # The set has a lower case — unlike the C64's — so prose that asks to keep its case
  # keeps it, at the same 23-character line every glyph screen holds.
  test 'teletext keeps case where the c64 cannot' do
    assert_equal ['The cat is a small'], TeletextGlyph.lines('The cat is a small', keep_case: true)
    assert_equal ['THE CAT IS A SMALL'], C64Glyph.lines('The cat is a small', keep_case: true)
    assert_equal C64Glyph::MAX_CHARS, TeletextGlyph::MAX_CHARS
  end

  # The charset is the machine's: no lower case, no accents, no typographic marks. What can
  # fold onto a character it had, folds; what cannot is shown as '?', which is honest about
  # what the screen cannot draw rather than a blank where a word was.
  test 'the c64 folds text onto the characters the machine had' do
    lines = C64Glyph.lines("café — “no” … °C\u{1F600}")

    assert_equal ['CAFE - "NO" ... °C?'], lines
  end

  test 'a c64 glyph never outgrows the width the frame leaves of the screen' do
    get glyph_url, params: { t: 'Chancellor announces surprise change to national insurance', s: 'c64' }

    width = @response.body[/width="(\d+)"/, 1].to_i

    assert_operator width, :<=, 212, 'the frame and its padding leave 212px of a 240px screen'
  end

  # The whole page on the C64: links as white bitmap glyphs, headings in the ink, the
  # forecast a handful of screen images — and an article's prose left as device text, where
  # reading comfort beats the look.
  test 'the c64 menu carries bitmap glyphs like the phosphor styles do' do
    get root_url, headers: { 'HTTP_COOKIE' => 'theme=c64;lat=51.5;city=Testville' }

    assert_match %r{<a accesskey="1"[^>]*><img src="/glyph\?l=1&amp;s=c64&amp;t=1\+Weather\+forecast"},
                 @response.body
    assert_match(/alt="1 Weather forecast"/, @response.body)
  end
end
