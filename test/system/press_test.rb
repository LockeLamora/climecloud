# frozen_string_literal: true

require 'application_system_test_case'

# A pressed link, button or submit inverts to white on blue with a highlight sweeping
# across it, and holds that for as long as the request takes. Over 4G that wait is long
# enough to doubt the keypress landed.
#
# These tests make the upstream genuinely slow and record the state from inside the
# outgoing page at unload, which is the far end of the wait. Selenium blocks until
# navigation completes, so the old document cannot be questioned while it is still up, and
# holding the mouse down instead would test :active rather than the wait.
class PressTest < ApplicationSystemTestCase
  SAVED = [{ 'id' => 's-one', 'name' => 'Northgate' }].freeze
  SLOW_UPSTREAM = 1.5

  setup do
    stub_api_credentials
    stub_request(:get, %r{transit\.land/api/v2/rest/stops\?}).to_return(json('stops' => []))
    stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures}).to_return do
      sleep SLOW_UPSTREAM
      json('stops' => [])
    end
    seed_cookies
  end

  teardown do
    unstub_api_credentials
    # Capybara resets cookies and the session between tests but not devtools overrides, so
    # an emulated media feature would otherwise apply to every test that runs after it.
    clear_emulated_media
  end

  test 'a pressed link stays inverted and animating for the whole request' do
    visit departures_url
    record_state_at_unload

    find('a', text: '1 Northgate').click
    state = recorded_state

    assert_equal 'A', state['tag']
    assert_equal '1 Northgate', state['text']
    assert state['focus'], 'focus is what spans the wait; without it there is no hook at all'
    assert_equal 'press-reveal', state['animation'], 'the pointer press should still be animating'
    # The inversion arrives as a sweep, so the blue is a growing background layer rather
    # than a flat colour, and the glyphs are painted by layers clipped to the text.
    assert_equal 'rgba(0, 0, 0, 0)', state['fill'], 'the glyphs are painted by the clipped layers'
    assert_includes state['clip'].to_s, 'text'
    assert_match(/rgb\(0, 0, 255\)/, state['image'], 'the blue that sweeps in must be a background layer')
  end

  # Mid-crossing the line is half inverted: white on blue up to the boundary, blue on white
  # after it. Read off the animation by parking it at a fraction of its own duration.
  test 'the inversion arrives progressively rather than all at once' do
    visit departures_url

    boundaries = [0.2, 0.5, 0.85].map { |fraction| boundary_at(fraction) }

    assert_operator boundaries[0], :<, boundaries[1], "the sweep did not advance: #{boundaries.inspect}"
    assert_operator boundaries[1], :<, boundaries[2], "the sweep did not advance: #{boundaries.inspect}"
    assert_operator boundaries[0], :<, 40, 'it should still be near the start a fifth of the way in'
    assert_operator boundaries[2], :>, 60, 'it should be most of the way across by the end'
  end

  # A news headline runs to several lines at 220px. A wrapping inline is painted as
  # fragments and its background is measured over those fragments joined together, which
  # puts the glyph-painting layers somewhere other than the glyphs; the text is transparent
  # by then, so the headline would render as a gap. No single-line link exercises this.
  test 'a headline that wraps stays visible while it is pressed' do
    stub_request(:get, /news\.google\.com/).to_return(body: file_fixture('news_response.xml').read)
    page.driver.browser.manage.add_cookie(name: 'country_code', value: 'gb')

    visit news_url
    # A single-source story's lead: the multi-source stories offer their links as short
    # outlet names, and only a full headline is long enough to wrap.
    link = all('.news button').find { |candidate| candidate.text.length > 40 }

    assert link, 'this test is only meaningful on a headline long enough to wrap'

    page.execute_script('arguments[0].focus()', link)

    assert_equal 1, page.evaluate_script('arguments[0].getClientRects().length', link),
                 'a pressed link must be one box, or the background is measured over joined fragments'
    assert_equal 'inline-block', style(link, 'display')
    assert_equal 'press-reveal', style(link, 'animationName')
    # The blue that paints the glyphs and the block behind them come from the same layers,
    # so if one is there the other is.
    assert_match(/rgb\(0, 0, 255\)/, style(link, 'backgroundImage'))
  end

  # f.submit renders an <input type="submit">, which needs its own selector alongside the
  # link and button rules. Planning a route is two upstream calls and a map image, so this
  # is the control with the longest wait behind it.
  test 'a pressed submit button inverts and sweeps like everything else' do
    visit directions_url

    button = find('input[type="submit"]')
    assert_equal 'none', style(button, 'animationName'), 'nothing should be running at rest'

    page.execute_script('arguments[0].focus()', button)

    assert_equal 'press-reveal', style(button, 'animationName')
    assert_includes style(button, 'backgroundClip'), 'text'
    assert_match(/rgb\(0, 0, 255\)/, style(button, 'backgroundImage'))
    # An input is already inline-block, so the box it paints into does not change.
    assert_equal 'inline-block', style(button, 'display')
  end

  # A reader who asked for no motion still sees the press. background-clip has to go back
  # to border-box along with the image: one layer takes only the first background-clip
  # value, and left at `text` the blue is clipped to the glyphs and renders white on
  # white.
  test 'reduced motion holds a readable inversion instead of animating' do
    emulate_reduced_motion
    visit departures_url

    link = find('a', text: '1 Northgate')
    page.execute_script('arguments[0].focus()', link)

    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches"),
           'the emulation did not take, so this proves nothing'
    assert_equal 'none', style(link, 'animationName')
    assert_equal 'border-box', style(link, 'backgroundClip'), 'blue clipped to the glyphs is invisible'
    assert_equal 'rgb(0, 0, 255)', style(link, 'backgroundColor')
    assert_equal 'rgb(255, 255, 255)', style(link, 'webkitTextFillColor')
  end

  # The keypad is the point of this app, so a number key gets everything a click gets,
  # sweep included. Chrome reports an access key as keyboard focus, so anything separating
  # pointer presses from keyboard ones would drop the sweep here.
  test 'a link reached by its access key sweeps for the whole request too' do
    visit departures_url
    record_state_at_unload

    press_access_key('1')
    state = recorded_state

    assert_equal '1 Northgate', state['text']
    assert_equal 'press-reveal', state['animation'], 'the keypad must get the sweep, not just the inversion'
    assert_match(/rgb\(0, 0, 255\)/, state['image'])
    assert_match(/departures_stop/, page.current_url, 'the access key must still follow the link')
  end

  # The posting button has to read the same as a link, since it looks like one.
  test 'a pressed button inverts like a link' do
    visit departures_url

    button = find('button', text: 'Forget saved stops')
    assert_equal 'rgb(0, 0, 255)', style(button, 'color'), 'a button at rest should look like a link'

    page.execute_script('arguments[0].focus()', button)

    assert_equal 'press-reveal', style(button, 'animationName')
    assert_match(/rgb\(0, 0, 255\)/, style(button, 'backgroundImage'))
    assert_includes style(button, 'backgroundClip'), 'text'
  end

  private

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def record_state_at_unload
    page.execute_script(<<~JS)
      addEventListener('beforeunload', () => {
        const el = document.activeElement;
        const s = el ? getComputedStyle(el) : null;
        sessionStorage.setItem('press', JSON.stringify({
          tag: el && el.tagName, text: el && el.textContent.trim(),
          focus: el && el.matches(':focus'), animation: s && s.animationName,
          fill: s && s.webkitTextFillColor, clip: s && s.backgroundClip,
          image: s && s.backgroundImage
        }));
      });
    JS
  end

  # Where the blue has reached, as a percentage of the line, with the animation parked at
  # a fraction of its duration by way of a negative delay.
  def boundary_at(fraction)
    link = find('a', text: '1 Northgate')
    page.execute_script(<<~JS, link, fraction)
      const el = arguments[0], f = arguments[1];
      el.focus();
      const seconds = parseFloat(getComputedStyle(el).animationDuration);
      el.style.animationDelay = `-${seconds * f}s`;
      el.style.animationPlayState = 'paused';
    JS
    style(link, 'backgroundSize').to_s[/([\d.]+)%/, 1].to_f
  end

  def emulate_reduced_motion
    page.driver.browser.execute_cdp(
      'Emulation.setEmulatedMedia',
      features: [{ 'name' => 'prefers-reduced-motion', 'value' => 'reduce' }]
    )
  end

  def clear_emulated_media
    page.driver.browser.execute_cdp('Emulation.setEmulatedMedia', features: [])
  rescue StandardError
    nil # no session left to clean up
  end

  def recorded_state
    raw = page.evaluate_script("sessionStorage.getItem('press')")

    assert raw.present?, 'nothing was recorded at unload, so the press was never observed'
    JSON.parse(raw)
  end

  # Chrome reaches an access key with Control+Option on macOS and Alt alone elsewhere, so
  # this picks by platform and reads the same on a laptop and on CI.
  def press_access_key(key)
    action = page.driver.browser.action
    if RbConfig::CONFIG['host_os'].match?(/darwin/)
      action.key_down(:control).key_down(:alt).send_keys(key).key_up(:alt).key_up(:control).perform
    else
      action.key_down(:alt).send_keys(key).key_up(:alt).perform
    end
    sleep 0.4 # let the navigation begin before anything is read back
  end

  def style(element, property)
    page.evaluate_script('getComputedStyle(arguments[0])[arguments[1]]', element, property)
  end

  def seed_cookies
    visit root_url
    { 'lat' => '51.5', 'lon' => '-0.1', 'city' => 'Testville' }.each do |name, value|
      page.driver.browser.manage.add_cookie(name: name, value: value)
    end
    page.driver.browser.manage.add_cookie(name: 'departures_saved', value: CGI.escape(SAVED.to_json))
  end
end
