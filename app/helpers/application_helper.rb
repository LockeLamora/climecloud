module ApplicationHelper
  # The styles whose glow can only reach the handset as an image. See PhosphorGlyph.
  PHOSPHOR_THEMES = %w[crt-green crt-amber plasma].freeze

  # On the phosphor styles every text link is drawn as a phosphor screen: the label goes to
  # the SVG endpoint and comes back as an image with the bloom and the raster baked in,
  # inside the same anchor, so the keypad and the access keys reach it exactly as before.
  #
  # Overridden here rather than changed at each call site, so every view keeps writing
  # plain link_to and every other style keeps plain text. Block and non-string forms pass
  # through untouched: those wrap markup of their own.
  def link_to(name = nil, options = nil, html_options = nil, &)
    return super if block_given? || !name.is_a?(String)
    return super unless PHOSPHOR_THEMES.include?(Themes.resolve(cookies[:theme]))

    super(options, html_options) { phosphor_glyph(name) }
  end

  # The alt is the label, so a failed image degrades to the plain text link it replaced.
  def phosphor_glyph(text)
    lines = PhosphorGlyph.lines(text)

    tag.img(src: phosphor_path(t: text), alt: text,
            width: PhosphorGlyph.width(lines), height: PhosphorGlyph.height(lines))
  end
  # The chosen palette, as a style block for the document head. See Themes::BASE_PALETTE
  # for why the palette is resolved here rather than left to var() in the stylesheet.
  #
  # Inline rather than a second stylesheet, for three reasons: it costs no extra request
  # over 4G; a cacheable stylesheet cannot vary by cookie, and the theme is a cookie; and
  # placed after the link tag it can reuse the components' own selectors verbatim —
  # `a, a:visited` rather than `body[data-theme="crt-amber"] a` — so each declaration
  # carries the same specificity as the value it supersedes and the orderings the
  # components rely on continue to hold. A descendant selector would outweigh `a:focus` in
  # components/press.css and suppress the pressed-link inversion.
  #
  # The body rule also declares the custom properties, for rules that take a token rather
  # than a colour: the sweep in components/press.css composes two of them into gradients.
  def theme_style_tag(theme)
    palette = Themes.palette(theme)
    # glow_ink is not a token. It is the alternative to one, written over it in the
    # @supports block rather than alongside it.
    tokens = palette.except(:glow_ink)
                    .map { |token, value| "--#{token.to_s.tr('_', '-')}:#{value}" }.join(';')

    css = <<~CSS
      body{#{tokens};background:#{palette[:paper]};color:#{palette[:ink]}}
      a,a:visited,a.change-settings,form.inline-action button{color:#{palette[:link]}}
      .error{color:#{palette[:error]}}
      .credit,.credit a,.credit a:visited{color:#{palette[:quiet]}}
      input[type="text"],input[type="submit"],select{background:#{palette[:paper]};color:#{palette[:ink]};border:1px solid #{palette[:quiet]}}
      th{background-color:#{palette[:head_bg]};color:#{palette[:head_ink]}}
      th,td{border-bottom:1px solid #{palette[:rule]}}
    CSS

    # Marked safe once the block is whole. Appending to an html_safe string escapes what is
    # appended, which turns the quotes in an attribute selector into entities.
    content_tag :style, (css + glow_ink_rule(palette)).html_safe
  end

  # The gem's own short name is the long official form for some countries ("United
  # Kingdom of Great Britain and Northern Ireland" for gb), which is no use on a narrow
  # screen. Its translations are both shorter and in the language the reader chose.
  def country_name(code)
    country = ISO3166::Country.new(code.to_s.upcase)
    return code.to_s.upcase if country.nil?

    country.translations[I18n.locale.to_s].presence || country.iso_short_name
  end

  private

  # Hands back the dimmer body text to a browser that will draw a wide soft bloom over it,
  # where the colour and the shadow share the brightness between them. The handset gets a
  # tighter halo than that and needs the colour to carry more of the load, which is what the
  # palette states outright.
  #
  # The condition asks about custom properties rather than about the shadow, for the reason
  # set out over the matching block in components/themes.css: the engine rendering for the
  # handset supports a text-shadow and cannot deliver the wide one, so it answers yes to the
  # wrong question. Custom properties are what actually separates the two paths.
  def glow_ink_rule(palette)
    glow = palette[:glow_ink]
    return '' if glow.blank?

    "@supports (color: var(--ink)){" \
      "body{--ink:#{glow};color:#{glow}}" \
      "input[type=\"text\"],input[type=\"submit\"],select{color:#{glow}}}\n"
  end
end
