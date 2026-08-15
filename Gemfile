# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.3.0'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.0.5', '>= 8.0.5.1'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem 'sprockets-rails'

# No database gem: no tables, and Active Record is not loaded. See config/application.rb.

# connection_pool 3.x is written in Ruby 3.4 syntax and will not parse on 3.3.0.
# Reached through wombat -> mechanize -> net-http-persistent.
gem 'connection_pool', '< 3.0'

# For webscraping news
gem 'domainatrix', '~> 0.0.11'
gem 'rexml', '~> 3.3', '>= 3.3.9'
gem 'wombat', '~> 3.0.0'

# Country names, translated, for confirming which country a postcode is in. Only the
# name lookup is used; there is no country dropdown, because the postcode answers that.
gem 'countries', '~> 5.7'

# TOTP codes for the 2FA page. The arithmetic is thirty lines of RFC 6238, but this is the
# library the ecosystem has audited for a decade, and one-time-password code is the wrong
# place to be the first reader of one's own bugs. No runtime dependencies.
gem 'rotp', '~> 6.3'

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '>= 5.0'

# No JavaScript, and no Hotwire. Every page is server-rendered and reached with plain
# links and forms, because the browsers this is built for run little or none of it.

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri windows]
end

# No development-only group: web-console works by injecting JavaScript into error pages,
# which is no use to a browser that runs none.

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'brakeman'
  gem 'bundle-audit'
  gem 'capybara'
  gem 'rubocop'
  # As with connection_pool, 4.46 is written in Ruby 3.4 syntax and will not parse
  # on 3.3.0, which takes every system test down at load.
  gem 'selenium-webdriver', '< 4.40'
  gem 'webmock'
end
