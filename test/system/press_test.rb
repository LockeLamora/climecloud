# frozen_string_literal: true

require 'application_system_test_case'

# Nothing on screen changed between pressing a link and the next page arriving, which
# over 4G is long enough to doubt the keypress landed. A pressed link now inverts to
# white on blue with a highlight sweeping across it, purely in CSS, for as long as the
# request takes.
#
# Only a real browser can hold :active, so this is the only place the behaviour can be
# checked. It is worth checking: the first attempt looked right in the stylesheet and
# rendered blue text on the blue ground, because components/text.css is concatenated
# after components/press.css and claimed :hover and :visited at the same weight. The
# pressed line was invisible and the CSS gave no hint of it.
class PressTest < ApplicationSystemTestCase
  SAVED = [{ 'id' => 's-one', 'name' => 'Northgate' },
           { 'id' => 's-two', 'name' => 'Market Square' }].freeze

  setup do
    stub_api_credentials
    # Releasing the hold completes the click, so wherever it lands needs a stub.
    stub_request(:get, %r{transit\.land/api/v2/rest}).to_return(
      status: 200, body: { 'stops' => [] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    seed_cookies
  end

  teardown { unstub_api_credentials }

  test 'a held link inverts to white on blue and animates' do
    visit departures_url

    link = find('a', text: '1 Northgate')
    assert_equal 'rgb(0, 0, 255)', style(link, 'color'), 'a link at rest should be blue'

    holding(link) do
      assert_equal 'rgb(255, 255, 255)', style(link, 'color'), 'pressed text must not stay blue on blue'
      assert_equal 'rgb(0, 0, 255)', style(link, 'backgroundColor')
      assert_equal 'press-sweep', style(link, 'animationName')
      assert_equal 'none', style(link, 'textDecorationLine')
    end
  end

  # The one button on this page posts rather than links, and has to read the same.
  test 'a held button inverts the same way as a link' do
    visit departures_url

    button = find('button', text: 'Forget saved stops')
    assert_equal 'rgb(0, 0, 255)', style(button, 'color'), 'a button at rest should look like a link'

    holding(button) do
      assert_equal 'rgb(255, 255, 255)', style(button, 'color')
      assert_equal 'rgb(0, 0, 255)', style(button, 'backgroundColor')
      assert_equal 'press-sweep', style(button, 'animationName')
    end
  end

  private

  def holding(element)
    page.driver.browser.action.click_and_hold(element.native).perform
    yield
  ensure
    page.driver.browser.action.release.perform
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
