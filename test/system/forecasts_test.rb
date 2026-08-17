# frozen_string_literal: true

require 'application_system_test_case'

class ForecastsTest < ApplicationSystemTestCase
  def setup
    visit '/'
    set_cookies
  end

  teardown do
    clear_viewport
  end

  # A forecast wider than the screen scrolls sideways, which on the handset costs the
  # single column reflow and drops the browser into a cursor this app has no keys for.
  # The rows are wrapping text lines, so nothing here should ever be wider than the page.
  # Measured at the real screen size, and at three text sizes, because the handset picks
  # its own and 16px is only what this desktop browser happens to use.
  test 'neither forecast is wider than the screen at any text size' do
    narrow_viewport

    %w[/forecast/hourly /forecast/daily].each do |path|
      stub_request(:get, /api\.open-meteo\.com/).to_return(
        body: file_fixture("#{path.split('/').last}_forecast.json").read
      )
      visit path

      assert_text ':00' if path.include?('hourly')

      ['', '12px', '24px'].each do |size|
        client, scroll = page.evaluate_script(<<~JS)
          (() => {
            document.documentElement.style.fontSize = '#{size}';
            return [document.documentElement.clientWidth,
                    document.documentElement.scrollWidth];
          })()
        JS

        at = size.presence || 'the default size'

        assert_equal client, scroll, "#{path} scrolls sideways at #{at}"
      end
    end
  end

  test 'visiting the hourly forecast' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('hourly_forecast.json').read)
    visit '/forecast/hourly'
    # The units live in the header line; each row carries the temperature with the feel
    # in brackets, and snow carries its own unit.
    assert_text 'Time °C'
    assert_text '18:00'
    assert_text '6°(3)'
    assert_text 'SNOW 53cm'
  end

  test 'visiting the hourly forecast and clicking on daily' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('daily_forecast.json').read)
    visit 'forecast/daily'
    assert_text 'Date °C'
    # The year is dropped: this is seven days out on a 240px line.
    assert_text '03-06'
    assert_no_text '2024-03-06'
    # A range with no unit of its own: the header carries it once.
    assert_text '2-11'
    assert_text 'SNOW 53cm'
  end
end
