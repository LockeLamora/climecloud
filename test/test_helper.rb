# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'

module ActiveSupport
  class TestCase
    # Deliberately serial. Rails only parallelises past fifty tests, and when the suite
    # crossed that line every worker went looking for a database of its own
    # ("rails_test-0" and friends) that nothing creates, so the run stalled. Almost
    # every test here waits on a stubbed HTTP call rather than the database, and the
    # whole suite finishes in a couple of seconds, so there is nothing to win back.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Nothing but the test server itself. The allow list that used to sit here named six
    # API hosts, which meant a test that forgot to stub one quietly made a real call and
    # passed on someone else's data: the settings tests geocoded live, so their assertions
    # had to be loosened to tolerate whatever came back, they needed real credentials, and
    # they could not run offline at all. Raising on an unstubbed request turns a forgotten
    # stub back into a failure that says so.
    WebMock.disable_net_connect!(allow_localhost: true)

    # config/master.key is not in the repo, so credentials do not decrypt under test.
    # Anything reaching an API needs stand-in keys to get as far as the stubbed request.
    # Defined by hand rather than with Minitest's stub, which handed back nil here.
    def stub_api_credentials
      credentials = ActiveSupport::OrderedOptions.new
      %w[google geoapify transitland].each do |service|
        credentials[service] = ActiveSupport::OrderedOptions.new
        credentials[service].api_key = "test-#{service}-key"
      end

      Rails.application.define_singleton_method(:credentials) { credentials }
    end

    def unstub_api_credentials
      singleton = Rails.application.singleton_class

      singleton.send(:remove_method, :credentials) if singleton.method_defined?(:credentials)
    end

    def with_api_credentials
      stub_api_credentials
      yield
    ensure
      unstub_api_credentials
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
