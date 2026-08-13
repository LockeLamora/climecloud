# frozen_string_literal: true

# The display treatments a reader can choose in settings. The name is written to a cookie
# and reappears as a data-theme attribute on the body, which app/assets/stylesheets/
# components/themes.css keys off.
module Themes
  # What the app looks like with no theme chosen: black on white with blue links.
  DEFAULT = 'unstyled'

  # Ordered as the dropdown offers them: how the light is made, brightest first, with the
  # plain look at the top because it is the default.
  NAMES = %w[
    unstyled
    crt-green
    crt-amber
    plasma
    teletext
    flap
    dmg
    stn
    nokia
    eink
    oled
  ].freeze

  def self.supported?(name)
    NAMES.include?(name.to_s)
  end

  # Anything unrecognised becomes the default, so a stale or hand-edited cookie cannot put
  # an arbitrary string into the markup.
  def self.resolve(name)
    supported?(name) ? name.to_s : DEFAULT
  end
end
