# frozen_string_literal: true

# The display treatments a reader can choose in settings. The name is written to a cookie
# and reappears as a data-theme attribute on the body, which app/assets/stylesheets/
# components/themes.css keys off.
module Themes
  # What the app looks like with no theme chosen: black on white with blue links.
  DEFAULT = 'unstyled'

  # Ordered as the dropdown offers them: alphabetically by the name a reader sees, with the
  # plain look first because it is the default. Alphabetical by the English name, so the
  # order stays the same whichever language the names are read in.
  NAMES = %w[
    unstyled
    crt-amber
    barbie
    stn
    c64
    flap
    eink
    dmg
    crt-green
    nokia
    oled
    plasma
    teletext
    workbench
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
