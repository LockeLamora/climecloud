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
  #   rule       hairlines
  #   emphasis   headings and bold
  #   head_bg    the filled block behind a table column header
  #   head_ink   text on that block
  #   error      a line that says something went wrong
  #
  # One optional colour goes with them:
  #
  #   glow_ink   body text where the bloom behind it will be drawn
  #
  # The phosphor styles set their body text dim and let a text-shadow carry the brightness,
  # which reads as an emitting screen. Opera Mini draws no shadow, so the dim value arrives
  # on its own and the screen looks washed out. Where a style declares glow_ink, ink is the
  # brightness the text needs unaided and glow_ink is the dimmer value a browser that will
  # draw the bloom uses instead.
  BASE_PALETTE = {
    paper: '#ffffff',
    ink: '#111111',
    link: 'blue',
    press_bg: 'blue',
    press_ink: '#ffffff',
    quiet: '#767676',
    rule: '#d8d8d8',
    emphasis: '#000000',
    head_bg: '#04AA6D',
    head_ink: '#ffffff',
    error: 'red'
  }.freeze

  # Each theme states only what it changes; the rest comes from BASE_PALETTE. Typography
  # and surface treatments — monospace faces, glow, scanlines, card and bevel effects —
  # belong to components/themes.css, keyed off the same data-theme attribute.
  PALETTES = {
    'unstyled' => {},

    # The three emissive styles carry one hue at two intensities: body text dim, anything
    # pressable at full brightness. ink is set part of the way towards link, far enough to
    # hold up without the bloom and short enough that the link is still the brighter of the
    # two — which is the only thing marking a link on these styles, since they drop the
    # underline.
    'crt-green' => { paper: '#060D07', ink: '#41DF7A', glow_ink: '#35C96C', link: '#52FF8F',
                     press_bg: '#52FF8F', press_ink: '#041006', quiet: '#1E7A42',
                     rule: '#14411F', emphasis: '#52FF8F', head_bg: '#52FF8F',
                     head_ink: '#041006' },

    'crt-amber' => { paper: '#0C0803', ink: '#E09B2B', glow_ink: '#CC8A20', link: '#FFB43C',
                     press_bg: '#FFB43C', press_ink: '#140C02', quiet: '#8A5E18',
                     rule: '#3D2A0C', emphasis: '#FFB43C', head_bg: '#FFB43C',
                     head_ink: '#140C02' },

    'plasma' => { paper: '#0A0402', ink: '#E55E13', glow_ink: '#D4550F', link: '#FF6B18',
                  press_bg: '#FF6B18', press_ink: '#0A0402', quiet: '#7E3309',
                  rule: '#3A1607', emphasis: '#FF6B18', head_bg: '#FF6B18',
                  head_ink: '#0A0402' },

    'teletext' => { paper: '#000000', ink: '#FFFFFF', link: '#00FFFF', press_bg: '#00FFFF',
                    press_ink: '#000000', quiet: '#FF00FF', rule: '#0000AA',
                    emphasis: '#FFFF00', head_bg: '#0000AA', head_ink: '#FFFF00' },

    'flap' => { paper: '#0B0B0C', ink: '#D9A62A', link: '#FFC533', press_bg: '#FFC533',
                press_ink: '#0B0B0C', quiet: '#6E5518', rule: '#26262A',
                emphasis: '#FFC533', head_bg: '#FFC533', head_ink: '#0B0B0C' },

    'dmg' => { paper: '#9BBC0F', ink: '#0F380F', link: '#0F380F', press_bg: '#0F380F',
               press_ink: '#9BBC0F', quiet: '#306230', rule: '#306230',
               emphasis: '#0F380F', head_bg: '#0F380F', head_ink: '#9BBC0F' },

    'stn' => { paper: '#12305E', ink: '#BFE9FF', link: '#7FD0F5', press_bg: '#BFE9FF',
               press_ink: '#12305E', quiet: '#6B93B8', rule: '#2B5688',
               emphasis: '#FFFFFF', head_bg: '#BFE9FF', head_ink: '#12305E' },

    'nokia' => { paper: '#C7D66B', ink: '#1B2410', link: '#1B2410', press_bg: '#1B2410',
                 press_ink: '#C7D66B', quiet: '#4A5330', rule: '#4A5330',
                 emphasis: '#1B2410', head_bg: '#1B2410', head_ink: '#C7D66B' },

    'eink' => { paper: '#F4F2ED', ink: '#23231F', link: '#23231F', press_bg: '#23231F',
                press_ink: '#F4F2ED', quiet: '#7C7973', rule: '#C9C6BE',
                emphasis: '#000000', head_bg: '#23231F', head_ink: '#F4F2ED' },

    'oled' => { paper: '#000000', ink: '#F2F4F7', link: '#6FA8FF', press_bg: '#6FA8FF',
                press_ink: '#000000', quiet: '#4A505A', rule: '#1C1F24',
                emphasis: '#FFFFFF', head_bg: '#1C1F24', head_ink: '#F2F4F7' },

    'workbench' => { paper: '#A8A8A8', ink: '#000000', link: '#000000', press_bg: '#0055AA',
                     press_ink: '#FFFFFF', quiet: '#4A4A4A', rule: '#000000',
                     emphasis: '#000000', head_bg: '#0055AA', head_ink: '#FFFFFF' },

    'c64' => { paper: '#352879', ink: '#8578CF', link: '#FFFFFF', press_bg: '#FFFFFF',
               press_ink: '#352879', quiet: '#6C5EB5', rule: '#6C5EB5',
               emphasis: '#FFFFFF', head_bg: '#FFFFFF', head_ink: '#352879' },

    # Red sits too close to this theme's paper to read as an error, so error takes the
    # darkest value in the palette instead.
    'barbie' => { paper: '#F92E8C', ink: '#FFFFFF', link: '#FFE300', press_bg: '#FFE300',
                  press_ink: '#A8005A', quiet: '#FFB3D8', rule: '#FF7EB8',
                  emphasis: '#FFE300', head_bg: '#FFE300', head_ink: '#A8005A',
                  error: '#2E0014' },

    'barbie-dark' => { paper: '#0C0209', ink: '#B01A67', link: '#FF2E9A', press_bg: '#FF2E9A',
                       press_ink: '#0C0209', quiet: '#6E1141', rule: '#3A0A22',
                       emphasis: '#FFFFFF', head_bg: '#FF2E9A', head_ink: '#0C0209' }
  }.freeze

  # Always a full palette, so the caller never has to know which values a theme chose to
  # leave alone.
  def self.palette(name)
    BASE_PALETTE.merge(PALETTES.fetch(resolve(name)))
  end
end
