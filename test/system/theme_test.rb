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
  setup do
    stub_api_credentials
    stub_request(:get, %r{transit\.land/api/v2/rest}).to_return(
      status: 200, body: { 'stops' => [] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    seed_location
  end

  teardown { unstub_api_credentials }

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

  # Brightness says it on a phosphor screen, so an underline is noise.
  test 'the phosphor styles do not underline their links' do
    %w[crt-green crt-amber plasma].each do |name|
      visit_with_theme(name)

      assert_equal 'none', style('a', 'textDecorationLine'), "#{name} still underlines its links"
    end
  end

  # Two colours and nothing else, so the underline is the only lever left.
  test 'the two-colour screens keep their underlines' do
    %w[dmg nokia].each do |name|
      visit_with_theme(name)

      assert_equal 'underline', style('a', 'textDecorationLine'), "#{name} has no way left to mark a link"
    end
  end

  private

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
