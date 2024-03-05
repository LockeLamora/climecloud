# frozen_string_literal: true

require 'application_system_test_case'

class SettingsTest < ApplicationSystemTestCase
  test 'successfully sets user settings' do
    visit settings_url
    assert_text 'Change your settings:'

    find_field(name: 'postcode').set('78000')
    select('France', from: 'country_code')
    choose(option: 'metric')
    check(name: 'mapimages')
    click_button(name: 'commit')

    sleep 2
    assert_match(page.driver.browser.manage.cookie_named('lat')[:value], '48.8051741')
    assert_match(page.driver.browser.manage.cookie_named('lon')[:value], '2.1219587')
    assert_match(page.driver.browser.manage.cookie_named('city')[:value], 'Versailles')
    assert_match(page.driver.browser.manage.cookie_named('metrics')[:value], 'metric')
    assert_match(page.driver.browser.manage.cookie_named('timezone_name')[:value], 'Europe%2FParis')
    assert_match(page.driver.browser.manage.cookie_named('state')[:value], 'Ile-de-France')
    assert_match(page.driver.browser.manage.cookie_named('show_map')[:value], '1')
    assert_match(page.driver.browser.manage.cookie_named('country_code')[:value], 'fr')
  end

  test 'usuccessfully sets user settings and an error is displayed' do
    visit settings_url
    assert_text 'Change your settings:'

    find_field(name: 'postcode').set('abcdefg')
    click_button(name: 'commit')

    sleep 2
    assert_text('Could not determine location, please try again')
  end
end
