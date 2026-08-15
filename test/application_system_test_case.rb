# frozen_string_literal: true

require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
  # driven_by :selenium, using: :chrome, screen_size: [1400, 1400]

  private

  # The screen this app is built for. Headless Chrome will not make a window narrower than
  # about 500px, so the real viewport is emulated through devtools instead.
  def narrow_viewport
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride',
                                    width: 240, height: 320, deviceScaleFactor: 1, mobile: true)
  end

  # A devtools override outlives the session reset between tests, so anything that sets one
  # has to clear it in teardown.
  def clear_viewport
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
  rescue StandardError
    nil
  end
end
