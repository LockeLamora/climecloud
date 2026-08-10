# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    WebMock.disable_net_connect!(
      allow_localhost: true,
      allow: ['maps.googleapis.com',
              'api.geoapify.com',
              'api.open-meteo.com',
              'news.google.com',
              'www.theguardian.com',
              'www.bbc.com']
    )

    # config/master.key is not in the repo, so credentials do not decrypt under test.
    # Anything reaching an API needs stand-in keys to get as far as the stubbed request.
    # Defined by hand rather than with Minitest's stub, which handed back nil here.
    def with_api_credentials
      credentials = ActiveSupport::OrderedOptions.new
      credentials.google = ActiveSupport::OrderedOptions.new
      credentials.google.api_key = 'test-google-key'
      credentials.geoapify = ActiveSupport::OrderedOptions.new
      credentials.geoapify.api_key = 'test-geoapify-key'

      application = Rails.application
      application.define_singleton_method(:credentials) { credentials }

      begin
        yield
      ensure
        application.singleton_class.send(:remove_method, :credentials)
      end
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
      page.driver.browser.manage.add_cookie(name: 'news_default_section', value: 'Headlines')
    end
  end
end
