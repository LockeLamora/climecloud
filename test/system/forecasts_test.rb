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

  # A table is laid out from its contents unless it is told otherwise, so the four columns
  # here were wider than the screen and the page scrolled sideways. On the handset that
  # costs the single column reflow and drops the browser into a cursor, which this app has
  # no keys for. Measured at the real screen size, and at three text sizes, because the
  # handset picks its own and 16px is only what this desktop browser happens to use.
  test 'neither forecast is wider than the screen at any text size' do
    stub_request(:get, /api\.open-meteo\.com/).to_return(body: file_fixture('hourly_forecast.json').read)
    narrow_viewport

    %w[/forecast/hourly /forecast/daily].each do |path|
      stub_request(:get, /api\.open-meteo\.com/).to_return(
        body: file_fixture("#{path.split('/').last}_forecast.json").read
      )
      visit path

      assert_selector 'th'

      ['', '12px', '24px'].each do |size|
        client, scroll, table = page.evaluate_script(<<~JS)
          (() => {
            document.documentElement.style.fontSize = '#{size}';
            return [document.documentElement.clientWidth,
                    document.documentElement.scrollWidth,
                    document.querySelector('table').getBoundingClientRect().width];
          })()
        JS

        at = size.presence || 'the default size'

        assert_equal client, scroll, "#{path} scrolls sideways at #{at}"
        assert_operator table, :<=, client, "#{path} draws its table wider than the screen at #{at}"
      end
    end
  end

  test 'visiting the hourly forecast' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('hourly_forecast.json').read)
    visit '/forecast/hourly'
    assert_text 'feels like'
    assert_text '18:00'
    assert_text '6°C(3)'
    assert_text 'snow: 53.45cm'
  end

  test 'visiting the hourly forecast and clicking on daily' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('daily_forecast.json').read)
    visit 'forecast/daily'
    assert_text 'Temp'
    # The year is dropped: seven days out, in a 54px column.
    assert_text '03-06'
    assert_no_text '2024-03-06'
    # The unit once, at the end of the range.
    assert_text '2 - 11mph'
    assert_text 'snow: 53.45cm'
  end
end
