# frozen_string_literal: true

require 'application_system_test_case'

# A theme reaches a page from two directions: its palette from the style block that
# ApplicationHelper#theme_style_tag writes into the head, and its treatment from
# components/themes.css, both keyed off data-theme on the body. Only a browser can say what
# the two resolve to together, so this asks Chrome for the computed value rather than
# checking the attribute or reading the stylesheet.
#
# Colour assertions here therefore cover the head block as much as the stylesheet.
# ThemePaletteTest covers the markup it emits.
class ThemeTest < ApplicationSystemTestCase
  # Stands in for a static map: the smallest thing the browser will accept as an image.
  ONE_PIXEL_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='

  setup do
    stub_api_credentials
    stub_request(:get, %r{transit\.land/api/v2/rest}).to_return(
      status: 200, body: { 'stops' => [] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    seed_location
  end

  teardown do
    unstub_api_credentials
    clear_viewport
  end

  test 'the plain style leaves the page black on white with blue links' do
    visit_with_theme('unstyled')

    assert_equal 'rgb(255, 255, 255)', style('body', 'backgroundColor')
    assert_equal 'rgb(17, 17, 17)', style('body', 'color')
    assert_equal 'rgb(0, 0, 255)', style('a', 'color')
  end

  test 'green phosphor repaints the page and its links' do
    visit_with_theme('crt-green')

    assert_equal 'rgb(6, 13, 7)', style('body', 'backgroundColor')
    # One hue, two intensities: dim body text, full brightness for the link.
    assert_equal 'rgb(53, 201, 108)', style('body', 'color')
    assert_equal 'rgb(82, 255, 143)', style('a', 'color')
    assert_includes style('body', 'fontFamily'), 'mono'
    assert_not_equal 'none', style('body', 'textShadow'), 'the phosphor bloom is the point'
  end

  test 'a press inverts in the theme colours rather than blue' do
    visit_with_theme('crt-amber')

    link = first('a')
    page.execute_script('arguments[0].focus()', link)

    # press.css reaches the palette through --press-bg, the blue behind it being only a
    # default, so an amber screen inverts amber.
    assert_match(/rgb\(255, 180, 60\)/, page.evaluate_script(
                                          'getComputedStyle(arguments[0]).backgroundImage', link
                                        ), 'the sweep should be the theme colour, not blue')
  end

  test 'e-ink is paper and ink with no glow at all' do
    visit_with_theme('eink')

    assert_equal 'rgb(244, 242, 237)', style('body', 'backgroundColor')
    assert_equal 'rgb(35, 35, 31)', style('body', 'color')
    assert_equal 'none', style('body', 'textShadow'), 'e-ink emits nothing'
  end

  # Compared as a set rather than by background alone: teletext and OLED are both honestly
  # pure black, and what tells them apart is the text and link colour on top of it.
  test 'every offered style resolves to colours of its own' do
    palettes = Themes::NAMES.to_h do |name|
      visit_with_theme(name)
      [name, [style('body', 'backgroundColor'), style('body', 'color'), style('a', 'color')]]
    end

    duplicates = palettes.group_by { |_, palette| palette }.select { |_, group| group.length > 1 }

    assert_empty duplicates, "these styles resolve identically, so one is not applying: #{duplicates}"
    assert_equal Themes::NAMES.length, palettes.length
  end

  # A table column header is a filled block, so it follows the style like everything else
  # rather than keeping its own green.
  test 'the forecast column headers follow the chosen style' do
    stub_request(:get, /api\.open-meteo\.com/).to_return(
      status: 200, body: file_fixture('hourly_forecast.json').read,
      headers: { 'Content-Type' => 'application/json' }
    )

    page.driver.browser.manage.add_cookie(name: 'theme', value: 'crt-amber')
    visit '/forecast/hourly'

    assert_selector 'th'
    assert_equal 'rgb(255, 180, 60)', style('th', 'backgroundColor'), 'the header kept its own green'
    assert_equal 'rgb(20, 12, 2)', style('th', 'color')
  end

  # A departure board has no underlines: the card is what says a row can be pressed. The
  # card is a background-color and the hinge a pseudo-element, because a background-image
  # here outranks the sweep in press.css and the row goes black on press instead.
  test 'the departure board draws rows as cards that still sweep when pressed' do
    visit_with_theme('flap')

    link = first('a')

    assert_equal 'block', style('a', 'display')
    assert_equal 'none', style('a', 'textDecorationLine')
    assert_operator page.evaluate_script('arguments[0].getBoundingClientRect().width', link), :>, 200,
                    'a board row should fill the column, not shrink to its text'

    page.execute_script('arguments[0].focus()', link)

    assert_equal 'press-reveal', page.evaluate_script('getComputedStyle(arguments[0]).animationName', link)
    assert_match(/rgb\(255, 197, 51\)/,
                 page.evaluate_script('getComputedStyle(arguments[0]).backgroundImage', link),
                 'the sweep layers were replaced by the card, so the row goes black')
  end

  # A phosphor style is a lit tube, and everything that says so on a browser drawing its own
  # page — the bloom, the scanlines over the text, the vignette — is a compositing effect
  # that cannot reach the handset. What is left there has to be the ground: a tint of the
  # style's own hue rather than black, since a tube at rest is never quite off, and a raster
  # tiled into the background rather than drawn over the glyphs.
  test 'a phosphor style is a lit screen where no bloom can be drawn' do
    %w[crt-green crt-amber plasma].each do |name|
      visit_with_theme(name)

      paper, raster, shadow = page.evaluate_script(<<~JS)
        (() => {
          for (const sheet of document.styleSheets) {
            for (let i = sheet.cssRules.length - 1; i >= 0; i--) {
              if (sheet.cssRules[i].conditionText) sheet.deleteRule(i);
            }
          }
          const style = getComputedStyle(document.body);
          return [style.backgroundColor, style.backgroundImage, style.textShadow];
        })()
      JS

      assert_equal 'none', shadow, 'the shadow is meant to be the gated half of this'
      assert_includes raster, name,
                      "#{name}: the ground carries no raster, so the screen is flat colour"

      # A tint of the hue and not black: two of the three channels have to differ, or the
      # ground is a neutral dark and the style reads as a dark page rather than a screen.
      channels = paper.scan(/\d+/).first(3).map(&:to_i)

      assert_operator channels.max - channels.min, :>, 4,
                      "#{name}: the ground is neutral, so nothing but the text carries the hue"
    end
  end

  # Telling a name from what is written under it, which is a different question from whether
  # it can be pressed. A style with one ink and one paper spends the same colour on both, so
  # a list of places came out as one undifferentiated block. Weight is what those use, being
  # the only thing left that the handset can draw too.
  test 'a style with one ink tells a name from the lines under it by weight' do
    Themes::NAMES.each do |name|
      palette = Themes.palette(name)
      next unless palette[:ink] == palette[:link]

      visit_with_theme(name)

      # The styles that draw a box round every row do this job with the box instead.
      next if style('a', 'borderBottomStyle') != 'none' || style('a', 'boxShadow') != 'none'

      assert_operator style('a', 'fontWeight').to_i, :>, style('body', 'fontWeight').to_i,
                      "#{name}: a name is the same colour and the same weight as its details"
    end
  end

  # The rule rather than a list: a link has to carry at least one signal that it can be
  # pressed. Where the link colour differs from the body colour that is enough on its own and
  # an underline is noise. Where they are the same value — a screen with one ink and one
  # paper, or Workbench where everything is black — something else has to say it, which is an
  # underline, a border, or a bevel.
  #
  # The plain style is exempt: it is the default look, and its links are underlined.
  test 'every link carries at least one sign that it can be pressed' do
    (Themes::NAMES - ['unstyled']).each do |name|
      visit_with_theme(name)

      underlined = style('a', 'textDecorationLine') == 'underline'

      if style('a', 'color') == style('body', 'color')
        boxed = style('a', 'borderBottomStyle') != 'none' || style('a', 'boxShadow') != 'none'

        assert underlined || boxed,
               "#{name}: the link is the same colour as the body text and nothing else marks it"
      else
        assert_not underlined, "#{name}: the colour already says it, so the underline is noise"
      end
    end
  end

  # A shadow the handset cannot be given is not simply dropped on the way there: the engine
  # rendering for it computes one, writes it into a format with nowhere to put it, and a
  # trace lands on the first glyph of each word, which reads as that letter being bold. So
  # no phosphor style may declare a text-shadow outside the gated block.
  test 'no glow is declared where a browser that cannot deliver one would read it' do
    ungated = page.evaluate_script(<<~JS)
      (() => {
        const out = [];
        for (const sheet of document.styleSheets) {
          for (const rule of sheet.cssRules) {
            if (rule.style && rule.style.textShadow && rule.style.textShadow !== 'none') {
              out.push(rule.selectorText);
            }
          }
        }
        return out;
      })()
    JS

    assert_empty ungated,
                 "a glow declared here reaches a browser that turns it into an artefact: #{ungated}"

    # And it still has to be drawn where it can be.
    visit_with_theme('crt-amber')

    assert_not_equal 'none', style('body', 'textShadow')
  end

  # Anything held back from the handset has to be gated on custom properties, not on the
  # effect being held back.
  #
  # Opera Mini renders on Opera's servers with an engine that implements @supports and can
  # compute a text-shadow, a gradient and a fixed overlay; what it cannot do is carry any of
  # them through OBML to the phone. So a condition naming one of those answers for the
  # renderer rather than for the screen, answers yes, and switches off the plain styling the
  # handset was going to get. Custom properties are the one capability the two paths differ
  # on, which is why the palette is resolved server-side in the first place.
  #
  # press.css is exempt: its condition gates an effect for browsers that draw their own
  # pages, and the handset cannot show a press at all whichever way that one resolves.
  test 'the fallbacks are gated on custom properties rather than on what they replace' do
    conditions = page.evaluate_script(<<~JS)
      (() => {
        const out = [];
        const walk = rules => {
          for (const rule of rules) {
            if (rule.conditionText && rule.cssRules && !rule.media) out.push(rule.conditionText);
            if (rule.cssRules) walk(rule.cssRules);
          }
        };
        for (const sheet of document.styleSheets) walk(sheet.cssRules);
        return out;
      })()
    JS

    conditions.reject! { |c| c.include?('background-clip') }

    assert_not_empty conditions, 'no @supports block was found at all'
    conditions.each do |condition|
      assert_includes condition, 'var(',
                      "this asks what the renderer can compute, not what reaches the phone: #{condition}"
    end
  end

  # Making a link a row and taking away the break that used to separate it are one change,
  # not two, and a browser that applies one without the other gets a mess either way: all
  # the options run into a single paragraph, or every option is double spaced.
  #
  # Checked against what the browser computes rather than against the text of the selectors,
  # and with every :has() rule deleted from the live stylesheet first, which is what the
  # handset's browser does to them. What is left has to agree with itself: rows that are
  # still blocks need their breaks gone, and rows that have fallen back to running inline
  # need them kept. The board and Workbench make blocks in their own rules with no :has() in
  # the selector, so they carry their own suppression to match.
  test 'the rows and the breaks they replace stand or fall together without :has()' do
    (Themes::NAMES - ['unstyled']).each do |name|
      visit_with_theme(name)

      rows_without_has.compact.each do |kind, (display, following, gap)|
        assert_equal display == 'block', following == 'none',
                     "#{name}: the #{kind} is #{display} and the break after it is #{following}, " \
                     'so the options either run together or come out double spaced'
        next unless display == 'block'

        assert_operator gap, :>, 0,
                        "#{name}: the #{kind} is a row with nothing under it, so the rows sit flush"
      end
    end
  end

  # box-shadow does not survive the crossing to the handset any more than text-shadow does,
  # and Workbench's buttons arrived flat. The bevel is four border colours there, which is
  # how the machine it borrows from drew one and what the handset can still take; the shadow
  # version is restored only where there is something to draw it.
  test 'workbench keeps its bevel where no shadow can be drawn' do
    visit_with_theme('workbench')

    top, bottom, shadow = page.evaluate_script(<<~JS)
      (() => {
        for (const sheet of document.styleSheets) {
          for (let i = sheet.cssRules.length - 1; i >= 0; i--) {
            if (sheet.cssRules[i].conditionText) sheet.deleteRule(i);
          }
        }
        const style = getComputedStyle(document.querySelector('a'));
        return [style.borderTopColor, style.borderBottomColor, style.boxShadow];
      })()
    JS

    assert_equal 'none', shadow, 'the shadow is meant to be the gated half of this'
    assert_not_equal top, bottom,
                     'the button is flat without a shadow, so the handset sees no bevel at all'
  end

  # The views put a line break after any link meant to sit on its own line — one after a
  # stop, two on the main menu — so inline links have a thumb's worth of room. Every style
  # but the plain one turns those links into rows, and a row plus its old break would stack
  # into a blank line between every entry.
  test 'no style stacks a blank line between its rows' do
    (Themes::NAMES - ['unstyled']).each do |name|
      page.driver.browser.manage.add_cookie(name: 'theme', value: name)
      visit root_url

      pitch, outer = page.evaluate_script(<<~JS)
        (() => {
          const rows = [...document.querySelectorAll('a')].filter(el => el.offsetParent !== null);
          const first = rows[0].getBoundingClientRect();
          return [rows[1].getBoundingClientRect().top - first.top,
                  first.height + parseFloat(getComputedStyle(rows[0]).marginBottom)];
        })()
      JS

      assert_in_delta outer, pitch, 2,
                      "#{name} leaves #{(pitch - outer).round}px of blank line between rows"
    end
  end

  # The look anyone who never opens the dropdown gets: inline links, underlined.
  test 'the plain style keeps the inline links and the spacing the app shipped with' do
    visit_with_theme('unstyled')
    visit root_url

    assert_equal 'inline', style('a', 'display')
    assert_equal 'underline', style('a', 'textDecorationLine')
  end

  test 'the commodore border does not push the page wider than the screen' do
    narrow_viewport
    visit_with_theme('c64')

    assert_equal page.evaluate_script('document.documentElement.clientWidth'),
                 page.evaluate_script('document.documentElement.scrollWidth'),
                 'the border pushed the page wider than the screen'

    # The column takes what the frame leaves rather than a width of its own, which is the
    # only way the two can agree on a screen whose size is not known here.
    column, inside = page.evaluate_script(<<~JS)
      (() => {
        const body = getComputedStyle(document.body);
        return [document.querySelector('.route').getBoundingClientRect().width,
                document.body.clientWidth
                  - parseFloat(body.paddingLeft) - parseFloat(body.paddingRight)];
      })()
    JS

    assert_in_delta inside, column, 1, 'the column does not fill the space inside the frame'
  end

  # The screens this runs on differ by more than a factor of two, so the column is a ceiling
  # rather than a width: it takes what a narrow screen has and stops once the lines get long
  # enough to lose your place tracking back across them.
  test 'the reading column fills a narrow screen and is capped on a wide one' do
    narrow_viewport
    visit_with_theme('unstyled')

    narrow = page.evaluate_script("document.querySelector('.route').getBoundingClientRect().width")
    screen = page.evaluate_script('document.documentElement.clientWidth')

    assert_operator narrow, :>, screen * 0.8, 'the column leaves a narrow screen half empty'
    assert_operator narrow, :<=, screen

    clear_viewport
    visit_with_theme('unstyled')

    wide = page.evaluate_script("document.querySelector('.route').getBoundingClientRect().width")

    assert_operator wide, :>, narrow, 'the column does not grow with the screen at all'
    assert_operator wide, :<, page.evaluate_script('document.documentElement.clientWidth'),
                    'the column runs the full width of a desktop window'
  end

  # A style that draws a frame has to leave a gap inside it. The browser's body margin is
  # what keeps text off the screen edge everywhere else, and a border sits outside that
  # margin, so a framed style that keeps it has the frame 8px in and the text against it.
  #
  # Measured at three text sizes rather than one. A handset picks its own, and 16px is only
  # what this desktop browser happens to render at: the gap has to survive a larger size
  # without a sideways scroll, and a smaller one without disappearing.
  test 'no style sets its text against its own frame at any text size' do
    narrow_viewport

    (Themes::NAMES - ['unstyled']).each do |name|
      visit_with_theme(name)

      ['', '12px', '24px'].each do |size|
        border, gap, client, scroll = page.evaluate_script(<<~JS)
          (() => {
            document.documentElement.style.fontSize = '#{size}';
            const width = parseFloat(getComputedStyle(document.body).borderLeftWidth);
            const inside = document.body.getBoundingClientRect().left + width;
            return [width,
                    document.querySelector('.route').getBoundingClientRect().left - inside,
                    document.documentElement.clientWidth,
                    document.documentElement.scrollWidth];
          })()
        JS

        next if border.zero?

        at = size.presence || 'the default size'

        assert_operator gap, :>=, 4, "#{name} sets its text #{gap}px from its own frame at #{at}"
        assert_equal client, scroll, "#{name} scrolls sideways at #{at}"
      end
    end
  end

  # text-transform is not part of the font shorthand, so a control keeps its own case
  # unless told to inherit — which leaves the one button on the page in sentence case while
  # everything around it is capitals.
  test 'a style that uses capitals reaches the buttons too' do
    visit_with_theme('c64')

    assert_equal 'uppercase', style('a', 'textTransform')
    assert_equal 'uppercase', style('form.inline-action button', 'textTransform')
  end

  # The bevel is what says a row can be pressed, so the button face is a background-color:
  # an image there outranks the sweep in press.css and the row goes flat on press.
  test 'workbench rows are bevelled buttons that still sweep when pressed' do
    visit_with_theme('workbench')

    link = first('a')

    assert_equal 'block', style('a', 'display')
    assert_equal 'none', style('a', 'textDecorationLine')
    assert_includes style('a', 'boxShadow'), 'inset'

    page.execute_script('arguments[0].focus()', link)

    assert_equal 'press-reveal', page.evaluate_script('getComputedStyle(arguments[0]).animationName', link)
    assert_match(/rgb\(0, 85, 170\)/,
                 page.evaluate_script('getComputedStyle(arguments[0]).backgroundImage', link),
                 'the bevel replaced the sweep layers')
  end

  # A headline wraps to several lines at 220px, and the news list runs its articles together
  # with no break between them, so the rule that keys off a following <br> does not reach
  # them. A style that draws a box has to make every link a block or the box is drawn once
  # per line, and nothing may stick out past the screen.
  test 'the boxed styles draw one box per headline and stay inside the screen' do
    stub_request(:get, /news\.google\.com/).to_return(body: file_fixture('news_response.xml').read)
    narrow_viewport

    %w[flap workbench].each do |name|
      page.driver.browser.manage.add_cookie(name: 'theme', value: name)
      page.driver.browser.manage.add_cookie(name: 'country_code', value: 'gb')
      visit news_url

      assert_equal 'block', style('.news a', 'display'), "#{name} leaves headlines inline"
      assert_equal 1, page.evaluate_script("document.querySelector('.news a').getClientRects().length"),
                   "#{name} draws the box once per wrapped line"
      assert_equal page.evaluate_script('document.documentElement.clientWidth'),
                   page.evaluate_script('document.documentElement.scrollWidth'),
                   "#{name} pushes the news list wider than the screen"
    end
  end

  # A map is the only thing on any page carrying its information as picture rather than
  # text, and it is what someone is navigating by. Every screen treatment is a fixed
  # pseudo-element over the whole page, so each one is checked against the map: the image
  # has to outrank it, or the scanlines and the vignette land on the route.
  test 'no style draws its screen treatment over the map' do
    stub_route

    (Themes::NAMES - ['unstyled']).each do |name|
      page.driver.browser.manage.add_cookie(name: 'theme', value: name)
      visit '/directions_plan?origin=start+street&destination=end+street&mode=walking&view=turn&step=0'

      assert_selector '.route img'

      overlay, image = page.evaluate_script(<<~JS)
        (() => {
          const over = getComputedStyle(document.body, '::after');
          const img = getComputedStyle(document.querySelector('.route img'));
          return [over.content === 'none' ? null : over.zIndex, img.zIndex];
        })()
      JS

      next if overlay.nil?

      assert_operator image.to_i, :>, (overlay == 'auto' ? 0 : overlay.to_i),
                      "#{name} draws its screen treatment over the map"
    end
  end

  private

  # One turn of a walking route, which is the only page carrying a map.
  def stub_route
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/staticmap})
      .to_return(status: 200, body: Base64.decode64(ONE_PIXEL_PNG),
                 headers: { 'Content-Type' => 'image/png' })
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/directions/json})
      .to_return(status: 200, body: route_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def route_body
    {
      'status' => 'OK',
      'geocoded_waypoints' => [{ 'geocoder_status' => 'OK' }, { 'geocoder_status' => 'OK' }],
      'routes' => [{
        'overview_polyline' => { 'points' => 'overviewpoints' },
        'legs' => [{
          'start_address' => 'Start Road, Testville', 'end_address' => 'End Road, Testville',
          'start_location' => { 'lat' => 52.3, 'lng' => 1.17 },
          'end_location' => { 'lat' => 52.31, 'lng' => 1.18 },
          'duration' => { 'text' => '12 mins' },
          'steps' => [{
            'html_instructions' => 'Head north on Test Road',
            'distance' => { 'text' => '200 m', 'value' => 200 },
            'duration' => { 'text' => '3 mins' },
            'start_location' => { 'lat' => 52.3, 'lng' => 1.17 },
            'end_location' => { 'lat' => 52.31, 'lng' => 1.18 },
            # Empty rather than encoded: the step is walked from its endpoints instead.
            'polyline' => { 'points' => '' }
          }]
        }]
      }]
    }
  end

  # A row and the break after it, for a link and for a one-button form, with every :has()
  # rule dropped from the live stylesheet first the way the handset's browser drops them.
  # Either member is nil where the page carries no such element.
  def rows_without_has
    page.evaluate_script(<<~JS)
      (() => {
        for (const sheet of document.styleSheets) {
          for (let i = sheet.cssRules.length - 1; i >= 0; i--) {
            const sel = sheet.cssRules[i].selectorText;
            if (sel && sel.includes(':has(')) sheet.deleteRule(i);
          }
        }
        const pair = el => {
          if (!el) return null;
          const next = el.nextElementSibling;
          const inner = el.tagName === 'FORM' ? el.querySelector('button') : el;
          return [getComputedStyle(el).display,
                  next && next.tagName === 'BR' ? getComputedStyle(next).display : 'none',
                  parseFloat(getComputedStyle(inner).marginBottom)];
        };
        return {
          link: pair([...document.querySelectorAll('a')].find(el => el.offsetParent !== null)),
          button: pair(document.querySelector('form.inline-action'))
        };
      })()
    JS
  end

  def visit_with_theme(name)
    page.driver.browser.manage.add_cookie(name: 'theme', value: name)
    visit departures_url
  end

  def style(selector, property)
    page.evaluate_script(
      'getComputedStyle(document.querySelector(arguments[0]))[arguments[1]]', selector, property
    )
  end

  def seed_location
    visit root_url
    { 'lat' => '51.5', 'lon' => '-0.1', 'city' => 'Testville', 'country_code' => 'gb' }.each do |name, value|
      page.driver.browser.manage.add_cookie(name: name, value: value)
    end
    page.driver.browser.manage.add_cookie(
      name: 'departures_saved',
      value: CGI.escape([{ 'id' => 's-one', 'name' => 'Northgate' }].to_json)
    )
  end
end
