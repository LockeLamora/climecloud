# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'

module ActiveSupport
  class TestCase
    # Serial. Every test waits on a stubbed HTTP call and the whole suite runs in a couple
    # of seconds, so forking workers buys nothing.
    parallelize(workers: 1)

    # Nothing but the test server itself: an unstubbed request raises rather than reaching
    # a real API. No allow list, or a missing stub becomes a live call whose assertions have
    # to tolerate whatever comes back.
    WebMock.disable_net_connect!(allow_localhost: true)

    # Credentials are empty for every test unless a test asks for them.
    #
    # config/master.key is not in the repo, so credentials decrypt on a developer machine
    # and not on a CI runner. Blanking them here makes both behave the same, so a test that
    # needs keys fails in the place where it is cheap to fix.
    #
    # Anything reaching an API needs stand-in keys to get as far as its stubbed request:
    # call stub_api_credentials in setup, or wrap a section in with_api_credentials.
    setup { unstub_api_credentials }

    # Defined by hand rather than with Minitest's stub, which hands back nil here.
    def stub_api_credentials
      credentials = ActiveSupport::OrderedOptions.new
      %w[google geoapify transitland].each do |service|
        credentials[service] = ActiveSupport::OrderedOptions.new
        credentials[service].api_key = "test-#{service}-key"
      end

      replace_credentials_with(credentials)
    end

    # Empty rather than removing the override, which would hand back whatever
    # config/master.key decrypts to.
    def unstub_api_credentials
      replace_credentials_with(ActiveSupport::OrderedOptions.new)
    end

    def with_api_credentials
      stub_api_credentials
      yield
    ensure
      unstub_api_credentials
    end

    private

    def replace_credentials_with(credentials)
      Rails.application.define_singleton_method(:credentials) { credentials }
    end

    def set_cookies
      page.driver.browser.manage.add_cookie(name: 'lat', value: '48.8051741')
      page.driver.browser.manage.add_cookie(name: 'lon', value: '2.1219587')
      page.driver.browser.manage.add_cookie(name: 'city', value: 'Versailles')
      page.driver.browser.manage.add_cookie(name: 'metrics', value: 'metric')
      page.driver.browser.manage.add_cookie(name: 'timezone_name', value: 'Europe%2FParis')
      page.driver.browser.manage.add_cookie(name: 'state', value: 'Ile-de-France')
      page.driver.browser.manage.add_cookie(name: 'show_map', value: '1')
      page.driver.browser.manage.add_cookie(name: 'country_code', value: 'fr')
      page.driver.browser.manage.add_cookie(name: 'news_default_section', value: 'HEADLINES')
    end
  end
end
