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
    barbie-dark
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

  # The colours of each theme, held as data rather than as CSS.
  #
  # The target handset browses with Opera Mini 4.4, which renders on Opera's servers with a
  # Presto core predating CSS custom properties. It discards any declaration whose value is
  # a var() call, so a palette expressed only in custom properties has no effect there.
  #
  # The theme is a cookie, so the server knows the palette before it renders the page.
  # ApplicationHelper#theme_style_tag writes it into the head as ordinary declarations,
  # which that browser supports. The same block also declares the custom properties, for
  # the rules that need a token rather than a colour: the pressed-link sweep in
  # components/press.css composes two of them into gradients.
  #
  #   paper      page background
  #   ink        body text
  #   link       anything pressable
  #   press_bg   the block a press paints
  #   press_ink  text on that block
  #   quiet      the attribution line
  #   emphasis   headings and bold
  #   error      a line that says something went wrong
  #   good       a standing offer — eating a meal, drinking a draught — kept apart
  #              from the pressable things around it
  BASE_PALETTE = {
    paper: '#ffffff',
    ink: '#111111',
    link: 'blue',
    press_bg: 'blue',
    press_ink: '#ffffff',
    quiet: '#767676', emphasis: '#000000',
    error: 'red', good: 'green'
  }.freeze

  # Each theme states only what it changes; the rest comes from BASE_PALETTE. Typography
  # and surface treatments — monospace faces, glow, scanlines, card and bevel effects —
  # belong to components/themes.css, keyed off the same data-theme attribute.
  PALETTES = {
    'unstyled' => {},

    # The three emissive styles, taking every value from the reference bench: the ground,
    # the text, and the dim tone the attribution line uses. One brightness rather than two,
    # since on the bench the bloom is what separates a lit stroke from the ground and the
    # text is one colour throughout. components/themes.css leaves the underline on to mark
    # a link, the bench having no links to mark.
    # A screen that is already green writes its good news in yellow instead.
    'crt-green' => { paper: '#060D07', ink: '#52FF8F', link: '#52FF8F',
                     press_bg: '#52FF8F', press_ink: '#041006', quiet: '#2C8A50', emphasis: '#52FF8F',
                     good: '#EAFF52' },

    # The amber is cool-retro-term's own preset value, warmer and easier over a read
    # than the paler bench amber.
    'crt-amber' => { paper: '#0C0803', ink: '#FF8100', link: '#FF8100',
                     press_bg: '#FF8100', press_ink: '#140C02', quiet: '#9A6A22', emphasis: '#FF8100',
                     good: '#54E354' },

    'plasma' => { paper: '#0A0402', ink: '#FF6B18', link: '#FF6B18',
                  press_bg: '#FF6B18', press_ink: '#0A0402', quiet: '#8E3A0C', emphasis: '#FF6B18',
                  good: '#54E354' },

    # good is the set's own green primary, straight off the Ceefax palette.
    'teletext' => { paper: '#000000', ink: '#FFFFFF', link: '#00FFFF', press_bg: '#00FFFF',
                    press_ink: '#000000', quiet: '#FF00FF', emphasis: '#FFFF00',
                    good: '#00FF00' },

    'flap' => { paper: '#0B0B0C', ink: '#D9A62A', link: '#FFC533', press_bg: '#FFC533',
                press_ink: '#0B0B0C', quiet: '#6E5518', emphasis: '#FFC533',
                good: '#54E354' },

    'dmg' => { paper: '#9BBC0F', ink: '#0F380F', link: '#0F380F', press_bg: '#0F380F',
               press_ink: '#9BBC0F', quiet: '#306230', emphasis: '#0F380F' },

    'stn' => { paper: '#12305E', ink: '#BFE9FF', link: '#7FD0F5', press_bg: '#BFE9FF',
               press_ink: '#12305E', quiet: '#6B93B8', emphasis: '#FFFFFF',
               good: '#66E08A' },

    'nokia' => { paper: '#C7D66B', ink: '#1B2410', link: '#1B2410', press_bg: '#1B2410',
                 press_ink: '#C7D66B', quiet: '#4A5330', emphasis: '#1B2410' },

    'eink' => { paper: '#F4F2ED', ink: '#23231F', link: '#23231F', press_bg: '#23231F',
                press_ink: '#F4F2ED', quiet: '#7C7973', emphasis: '#000000' },

    'oled' => { paper: '#000000', ink: '#F2F4F7', link: '#6FA8FF', press_bg: '#6FA8FF',
                press_ink: '#000000', quiet: '#4A505A', emphasis: '#FFFFFF',
                good: '#4CD964' },

    'workbench' => { paper: '#A8A8A8', ink: '#000000', link: '#000000', press_bg: '#0055AA',
                     press_ink: '#FFFFFF', quiet: '#4A4A4A', emphasis: '#000000' },

    # Links take VIC-II white — one keystroke away on the machine, and the only thing
    # marking a link here — while headings keep the text's own light blue, as the boot
    # screen kept everything.
    # good is VIC-II green, colour key 5 on the machine itself.
    'c64' => { paper: '#352879', ink: '#8578CF', link: '#FFFFFF', press_bg: '#FFFFFF',
               press_ink: '#352879', quiet: '#6C5EB5', emphasis: '#8578CF',
               good: '#5CAB5E' },

    # Red sits too close to this theme's paper to read as an error, so error takes the
    # darkest value in the palette instead; good goes dark for the same reason.
    'barbie' => { paper: '#F92E8C', ink: '#FFFFFF', link: '#FFE300', press_bg: '#FFE300',
                  press_ink: '#A8005A', quiet: '#FFB3D8', emphasis: '#FFE300',
                  error: '#2E0014', good: '#0B4F22' },

    'barbie-dark' => { paper: '#0C0209', ink: '#B01A67', link: '#FF2E9A', press_bg: '#FF2E9A',
                       press_ink: '#0C0209', quiet: '#6E1141', emphasis: '#FFFFFF',
                       good: '#3BD16F' }
  }.freeze

  # Always a full palette, so the caller never has to know which values a theme chose to
  # leave alone.
  def self.palette(name)
    BASE_PALETTE.merge(PALETTES.fetch(resolve(name)))
  end
end
