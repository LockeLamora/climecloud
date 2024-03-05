# frozen_string_literal: true

require 'application_system_test_case'

class SettingsTest < ApplicationSystemTestCase
  test 'visiting the settings page' do
    visit settings_url
    assert_text 'Change your settings:'
  end
end
