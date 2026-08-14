# frozen_string_literal: true

require 'application_system_test_case'

# Themes are applied as data-theme on the body and read by components/themes.css. Only a
# browser can say whether the tokens resolve, so this asks Chrome what it computed rather
# than whether the attribute is in the markup.
#
# Every themed property is declared twice — the literal first, then var() — so a browser
# without custom property support keeps the plain colours. That fallback is why the tokens
# are checked through getComputedStyle and not by reading the stylesheet.
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

    # The blue in press.css is a fallback behind var(--press-bg), so an amber screen
    # must invert amber.
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

  # A table column header is a filled block, so it follows the style like everything else.
  # It was the last thing left painting its own green whatever was chosen.
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

  # The rule rather than a list: a link has to carry at least one signal that it can be
  # pressed. Where the link colour differs from the body colour that is enough on its own and
  # an underline is noise. Where they are the same value — a screen with one ink and one
  # paper, or Workbench where everything is black — something else has to say it, which is an
  # underline, a border, or a bevel.
  #
  # The plain style is exempt: it is the app as it was, and its links are underlined.
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

  # Untouched, so the app looks exactly as it did to anyone who never opens the dropdown.
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
    assert_equal 220,
                 page.evaluate_script("document.querySelector('.route').getBoundingClientRect().width").round
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

  # Headless Chrome will not make a window narrower than about 500px, so the real viewport
  # is emulated. Cleared in teardown: a devtools override outlives the session reset.
  def narrow_viewport
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride',
                                    width: 240, height: 320, deviceScaleFactor: 1, mobile: true)
  end

  def clear_viewport
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
  rescue StandardError
    nil
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
