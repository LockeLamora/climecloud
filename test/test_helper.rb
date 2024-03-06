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
              'www.theguardian.com',
            'www.bbc.com']
    )
  end
end
