module ApplicationHelper
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
    # The glow pair are not tokens. Each is the alternative to one that is, and is written
    # over it in the @supports block rather than alongside it.
    tokens = palette.except(:glow_ink, :glow_paper)
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

  # Hands back the dimmer text and the darker ground to a browser that will draw a bloom
  # over them, where the colour and the shadow share the brightness between them. Without a
  # bloom each has to carry it alone, which is what the palette states outright.
  #
  # The condition asks about custom properties rather than about the shadow, for the reason
  # set out over the matching block in components/themes.css: the engine rendering for the
  # handset supports a text-shadow and cannot deliver one, so it answers yes to the wrong
  # question. Custom properties are what actually separates the two paths.
  def glow_ink_rule(palette)
    ink = palette[:glow_ink]
    paper = palette[:glow_paper]
    return '' if ink.blank? && paper.blank?

    "@supports (color: var(--ink)){body{#{dim_body(ink, paper)}}#{dim_controls(ink, paper)}}\n"
  end

  def dim_body(ink, paper)
    [ink.present? ? "--ink:#{ink};color:#{ink}" : nil,
     paper.present? ? "--paper:#{paper};background:#{paper}" : nil].compact.join(';')
  end

  # The settings page is mostly controls, so they follow the ground and the ink.
  def dim_controls(ink, paper)
    declarations = [ink.present? ? "color:#{ink}" : nil,
                    paper.present? ? "background:#{paper}" : nil].compact
    return '' if declarations.empty?

    "input[type=\"text\"],input[type=\"submit\"],select{#{declarations.join(';')}}"
  end
end
