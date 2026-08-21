module ApplicationHelper
  # The styles whose text can only reach the handset as an image: the phosphor styles for
  # their glow, the C64 and teletext for their character sets. See PhosphorGlyph and
  # CellGlyph.
  PHOSPHOR_THEMES = %w[crt-green crt-amber plasma].freeze

  # The colour roles a glyph can be drawn in, each with the URL flag that names it: the
  # colour is baked into the cached image, so it must ride in the URL the cache is keyed
  # by. What colour each role actually is belongs to the theme — see Themes::PALETTES.
  GLYPH_ROLES = { link: :l, emphasis: :e, good: :g, error: :r }.freeze

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

    super(options, html_options) { glyph_image(name, role: :link) }
  end

  # button_to is left alone on every theme: any element inside a button costs the
  # handset's cursor a second stop, so buttons carry plain text — the theme's style
  # block colours it — and only anchors carry glyph images.

  # For text that is not a link: headings and titles, drawn in place by the views. A
  # heading is marked as one, for the styles that write their headings in a colour of
  # their own; a barred line — a choice whose kit or toll is missing — takes the error
  # colour the same way. Anything else, or any other theme, comes back as it went in.
  def glyph_text(text, heading: false, error: false)
    return text unless glyph_theme

    glyph_image(text, role: (:emphasis if heading) || (:error if error))
  end

  # The alt is the label, so a failed image degrades to the plain text link it replaced.
  # The theme rides in the URL because the response is cached long and per-hue, and the
  # role flag rides with it: the C64 writes its links and teletext its headings in
  # colours of their own, baked into the image.
  def glyph_image(text, keep_case: false, quiet: false, role: nil)
    renderer = glyph_renderer
    lines = renderer.lines(text, keep_case: keep_case, quiet: quiet)

    query = { t: text, s: glyph_theme, c: keep_case ? '1' : nil, q: quiet ? '1' : nil }
    query[GLYPH_ROLES.fetch(role)] = '1' if role
    tag.img(src: glyph_path(query),
            alt: text,
            width: renderer.width(lines, quiet: quiet),
            height: renderer.height(lines, quiet: quiet))
  end

  # A pressable choice in a list: a button in a small form of its own. A form is the one
  # thing the handset's prefetcher never fires, so these carry the choices whose GET
  # would spend something — saving a stop or a place, turning a page. The label stays
  # plain text on every style, the drawn ones included: the handset's cursor gives any
  # element inside a button a stop of its own, so a glyph image here made every list
  # entry two stops (and nothing tried avoids it — a CSS background glyph is not painted
  # at all, and an image input double-stops and does not submit). The theme's style
  # block colours the text instead: the link colour, or the good colour for the
  # provision class.
  def choice_button(label, url, params, token: true, accesskey: nil, css: nil)
    form_with url: url, authenticity_token: token, class: 'inline-action' do
      controls = params.map { |name, value| hidden_field_tag(name, value, id: nil) }
      controls << tag.button(label, type: 'submit', accesskey: accesskey, class: css)
      safe_join(controls)
    end
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
      form.inline-action button.provision{color:#{palette[:good]}}
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
