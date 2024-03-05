# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the settings page successfully' do
    get settings_url
    assert_response :success
    assert_match 'Change your settings', @response.body
  end
end
