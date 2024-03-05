require "application_system_test_case"

class IndexTest < ApplicationSystemTestCase
  def setup
    visit root_url
  end
  
  test "visiting the index with the cookie set" do
    page.driver.browser.manage.add_cookie(name: "lat", value: "5")
    visit root_url
    assert_selector "a", text: "Weather forecast"
    assert_selector "a", text: "Map directions"
    assert_selector "a", text: "News"
    assert_selector "a", text: "Change settings"
    page.assert_selector(:css, "a[href=\"/settings\"]")
  end

  test "visiting the index without the cookie set" do
    page.driver.browser.manage.delete_cookie('lat')
    visit root_url
    assert_text "Changes your settings:"
  end
end
