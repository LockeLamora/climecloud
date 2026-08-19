module ApplicationHelper
  # The styles whose text can only reach the handset as an image: the phosphor styles for
  # their glow, the C64 and teletext for their character sets. See PhosphorGlyph and
  # CellGlyph.
  PHOSPHOR_THEMES = %w[crt-green crt-amber plasma].freeze

  # On the glyph styles every text link is drawn as an image: the label goes to the SVG
  # endpoint and comes back with the style baked in — the bloom and the raster, or the
  # machine's pixels — inside the same anchor, so the keypad and the access keys reach it
  # exactly as before.
  #
  # Overridden here rather than changed at each call site, so every view keeps writing
  # plain link_to and every other style keeps plain text. Block and non-string forms pass
  # through untouched: those wrap markup of their own.
  def link_to(name = nil, options = nil, html_options = nil, &)
    return super if block_given? || !name.is_a?(String) || glyph_theme.nil?

    super(options, html_options) { glyph_image(name, link: true) }
  end

  # The one-button forms take the same treatment, or saving a stop and forgetting one sit
  # untreated between drawn links.
  def button_to(name = nil, options = nil, html_options = nil, &)
    return super if block_given? || !name.is_a?(String) || glyph_theme.nil?

    super(options, html_options) { glyph_button_label(name) }
  end

  # For text that is not a link: headings and titles, drawn in place by the views. A
  # heading is marked as one, for the styles that write their headings in a colour of
  # their own. Anything else, or any other theme, comes back as it went in.
  def glyph_text(text, heading: false)
    glyph_theme ? glyph_image(text, heading: heading) : text
  end

  # The alt is the label, so a failed image degrades to the plain text link it replaced.
  # The theme rides in the URL because the response is cached long and per-hue, and the
  # link and heading flags ride with it: the C64 writes its links and teletext its
  # headings in colours of their own, baked into the image.
  def glyph_image(text, keep_case: false, quiet: false, link: false, heading: false)
    renderer = glyph_renderer
    lines = renderer.lines(text, keep_case: keep_case, quiet: quiet)

    tag.img(src: glyph_path(t: text, s: glyph_theme, c: keep_case ? '1' : nil,
                            q: quiet ? '1' : nil, l: link ? '1' : nil,
                            e: heading ? '1' : nil),
            alt: text,
            width: renderer.width(lines, quiet: quiet),
            height: renderer.height(lines, quiet: quiet))
  end

  # The label inside a hand-written submit button, drawn like the generated ones: the
  # glyph styles get their glyph, every other style the plain text.
  def button_label(text)
    glyph_theme ? glyph_button_label(text) : text
  end

  # A button's glyph is painted as a background rather than placed inside it as an
  # image: the handset's cursor gives an image inside a button a focus stop of its own —
  # the wide box and then the narrow one — so every headline and stop took two presses
  # to scroll past. A background is part of the button, and the cursor stops once. An
  # image inside a link costs nothing, so links keep their <img> and its alt fallback.
  def glyph_button_label(text)
    renderer = glyph_renderer
    lines = renderer.lines(text)

    tag.span(text, class: 'glyph-button-label',
                   style: "background-image:url(#{glyph_path(t: text, s: glyph_theme, l: '1')});" \
                          "width:#{renderer.width(lines)}px;height:#{renderer.height(lines)}px")
  end

  # An attribution line, drawn like everything else but at the quiet size and in the dim
  # tone, as .credit keeps it elsewhere. The block form of link_to passes through the
  # glyph override untouched, which is what lets this choose its own image.
  def credit_link(text, url)
    return link_to(text, url, target: '_blank') unless glyph_theme

    link_to(url, target: '_blank') { glyph_image(text, quiet: true) }
  end

  # A table drawn as a terminal would draw it: each row one line, columns aligned by the
  # fixed-width cells themselves, the whole thing a handful of glyphs instead of a hundred
  # table cells. Eight rows to a glyph keeps every URL short and the request count low.
  def glyph_screen(rows)
    safe_join(rows.each_slice(8).map do |slice|
      tag.p(glyph_image(slice.join("\n")))
    end)
  end

  def glyph_theme
    theme = Themes.resolve(cookies[:theme])
    glyph_themes.include?(theme) ? theme : nil
  end

  # Computed on first use rather than held in a constant: naming GlyphController while
  # this module loads is circular whenever the controller's own load is what pulled the
  # helpers in, and the load order that hits it depends on which page runs first. The
  # half-loaded module that resulted took every view down with undefined glyph_text.
  def glyph_themes
    @glyph_themes ||= PHOSPHOR_THEMES + GlyphController::CHARSETS.keys
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

  def glyph_renderer
    GlyphController::CHARSETS.fetch(glyph_theme, PhosphorGlyph)
  end

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
