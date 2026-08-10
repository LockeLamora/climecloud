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
    select('Headlines', from: 'news_default_section')

    sleep 2
    # Loose because the exact coordinates come from a live geocoder and differ
    # between providers; the city assertion below is what pins the location.
    assert_match(/\A48\./, page.driver.browser.manage.cookie_named('lat')[:value])
    assert_match(/\A2\./, page.driver.browser.manage.cookie_named('lon')[:value])
    assert_match(page.driver.browser.manage.cookie_named('city')[:value], 'Versailles')
    assert_match(page.driver.browser.manage.cookie_named('metrics')[:value], 'metric')
    assert_match(page.driver.browser.manage.cookie_named('timezone_name')[:value], 'Europe%2FParis')
    # Geoapify's English rendering of Ile-de-France varies with the exact
    # coordinates, so match the region rather than pinning one transliteration.
    assert_match(/France/, page.driver.browser.manage.cookie_named('state')[:value])
    assert_match(page.driver.browser.manage.cookie_named('show_map')[:value], '1')
    assert_match(page.driver.browser.manage.cookie_named('country_code')[:value], 'fr')
    assert_match(page.driver.browser.manage.cookie_named('news_default_section')[:value], 'Headlines')
  end

  test 'unsuccessfully sets user settings and an error is displayed' do
    visit settings_url
    assert_text 'Change your settings:'

    find_field(name: 'postcode').set('abcdefg')
    click_button(name: 'commit')

    sleep 2
    assert_text('Could not determine location, please try again')
  end
end
