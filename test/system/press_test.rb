# frozen_string_literal: true

require 'application_system_test_case'

# Nothing on screen changed between pressing a link and the next page arriving, which
# over 4G is long enough to doubt the keypress landed. A pressed link now inverts to
# white on blue for as long as the request takes, with a highlight sweeping across it
# when the press came from a pointer.
#
# The first attempt keyed on :active and did not work at all: :active lasts from press to
# release, the navigation starts on release, so the whole wait happened after :active had
# gone. It showed as one flash. The test passed anyway, because it used click_and_hold to
# pin the mouse down — it proved the styling and never tested the situation. Hence the
# shape of these tests: the upstream is made genuinely slow, and the state is recorded
# from inside the outgoing page at unload, which is the far end of the wait. Selenium
# blocks until navigation completes, so the old document cannot be questioned directly
# while it is still up.
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

  teardown { unstub_api_credentials }

  test 'a pressed link stays inverted and animating for the whole request' do
    visit departures_url
    record_state_at_unload

    find('a', text: '1 Northgate').click
    state = recorded_state

    assert_equal 'A', state['tag']
    assert_equal '1 Northgate', state['text']
    assert state['focus'], 'focus is what spans the wait; without it there is no hook at all'
    assert_equal 'rgb(255, 255, 255)', state['colour'], 'pressed text must not stay blue on blue'
    assert_equal 'rgb(0, 0, 255)', state['background']
    assert_equal 'press-sweep', state['animation'], 'the pointer press should still be animating'
  end

  # The keypad is the point of this app, so a number key has to get everything a click
  # gets, sweep included. Chrome reports an access key as keyboard focus, so anything that
  # separates pointer presses from keyboard ones drops the sweep here — which is why
  # nothing in press.css does.
  test 'a link reached by its access key sweeps for the whole request too' do
    visit departures_url
    record_state_at_unload

    press_access_key('1')
    state = recorded_state

    assert_equal '1 Northgate', state['text']
    assert_equal 'rgb(255, 255, 255)', state['colour']
    assert_equal 'rgb(0, 0, 255)', state['background']
    assert_equal 'press-sweep', state['animation'], 'the keypad must get the sweep, not just the inversion'
    assert_match(/departures_stop/, page.current_url, 'the access key must still follow the link')
  end

  # The posting button has to read the same as a link, since it looks like one.
  test 'a pressed button inverts like a link' do
    visit departures_url

    button = find('button', text: 'Forget saved stops')
    assert_equal 'rgb(0, 0, 255)', style(button, 'color'), 'a button at rest should look like a link'

    page.execute_script('arguments[0].focus()', button)

    assert_equal 'rgb(255, 255, 255)', style(button, 'color')
    assert_equal 'rgb(0, 0, 255)', style(button, 'backgroundColor')
    assert_equal 'press-sweep', style(button, 'animationName')
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
          focus: el && el.matches(':focus'),
          colour: s && s.color, background: s && s.backgroundColor, animation: s && s.animationName
        }));
      });
    JS
  end

  def recorded_state
    raw = page.evaluate_script("sessionStorage.getItem('press')")

    assert raw.present?, 'nothing was recorded at unload, so the press was never observed'
    JSON.parse(raw)
  end

  # Chrome reaches an access key with Control+Option on macOS and Alt alone elsewhere.
  # Both are sent so this reads the same on a laptop and on CI.
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
