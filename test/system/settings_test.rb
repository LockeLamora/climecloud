# frozen_string_literal: true

require 'application_system_test_case'

class SettingsTest < ApplicationSystemTestCase
  test 'successfully sets user settings' do
    stub_postcode_search
    stub_reverse_lookup
    visit settings_url
    assert_text 'Change your settings:'

    find_field(name: 'postcode').set('78000')
    choose(option: 'metric')
    check(name: 'mapimages')
    select('Headlines', from: 'news_default_section')
    click_button(name: 'commit')

    # 78000 is a postcode in both France and Bosnia, so the country is confirmed after
    # the search rather than chosen from a dropdown before it.
    assert_text 'Which country is this postcode in?'
    click_link('France')

    # The confirmation page is the signal that the cookies have been written. Cookies are
    # read straight out of the browser and nothing waits on them, so assert on the page
    # first or the reads race the redirect.
    assert_text 'Location saved as:'
    assert_equal '48.8035403', cookie('lat')
    assert_equal '2.1266886', cookie('lon')
    assert_equal 'Versailles', cookie('city')
    assert_equal 'Ile-de-France', cookie('state')
    assert_equal 'Europe%2FParis', cookie('timezone_name')
    assert_equal 'metric', cookie('metrics')
    assert_equal '1', cookie('show_map')
    assert_equal 'fr', cookie('country_code')
    # The section is stored as Google names it, not as the reader sees it: the dropdown
    # shows the translated word and submits the value the feed URLs expect.
    assert_equal 'HEADLINES', cookie('news_default_section')
  end

  test 'unsuccessfully sets user settings and an error is displayed' do
    # Autocomplete stays fuzzy even when asked for a postcode, so nonsense comes back as
    # real postcodes elsewhere. Nothing here matches what was typed, so nothing is offered.
    stub_geoapify('autocomplete', 'geoapify_postcode_nonsense.json')
    visit settings_url
    assert_text 'Change your settings:'

    find_field(name: 'postcode').set('abcdefg')
    click_button(name: 'commit')

    assert_text 'Could not determine location, please try again'
  end

  private

  def cookie(name)
    page.driver.browser.manage.cookie_named(name)[:value]
  end

  # Searched twice: once for the postcode as typed, which turns up two countries, and
  # again once France has been chosen. WebMock prefers the last stub that matches, so the
  # filtered search has to be registered second.
  def stub_postcode_search
    stub_geoapify('autocomplete', 'geoapify_postcode_78000.json')
    stub_geoapify('autocomplete', 'geoapify_postcode_78000_fr.json',
                  query: { 'filter' => 'countrycode:fr' })
  end

  def stub_reverse_lookup
    stub_geoapify('reverse', 'geoapify_reverse_versailles.json')
  end

  def stub_geoapify(endpoint, fixture, query: nil)
    stub = stub_request(:get, %r{api\.geoapify\.com/v1/geocode/#{endpoint}})
    stub = stub.with(query: hash_including(query)) if query
    stub.to_return(status: 200,
                   body: file_fixture(fixture).read,
                   headers: { 'Content-Type' => 'application/json' })
  end
end
