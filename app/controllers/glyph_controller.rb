# frozen_string_literal: true

require 'phosphor_glyph'
require 'c64_glyph'
require 'teletext_glyph'
require 'themes'

# Text drawn as an image, served as SVG: a phosphor screen for the phosphor styles, the
# machine's own character set for the C64 and teletext. See PhosphorGlyph for why the glow
# has to travel this way — Opera's servers rasterise the SVG and send pixels, which is the
# one form in which blur, alpha and compositing reach the handset — and CellGlyph for why
# the fonts have to: no font a page names ever reaches the device.
class GlyphController < ApplicationController
  # The styles whose text is the shapes of a character generator ROM, each with its
  # renderer. Everything else drawn here is a phosphor screen.
  CHARSETS = { 'c64' => C64Glyph, 'teletext' => TeletextGlyph }.freeze

  # The bloom, per phosphor style: the hue at three radii, echoing the treatment a
  # compositing browser draws over the page text — a tight ring, the glow, and the wide
  # spill.
  BLUR_RADII = [0.6, 2.5, 6].freeze
  # The raster: one line in three, at the depth the page-wide treatment uses.
  SCAN_OPACITY = 0.32

  # The theme comes in the URL rather than off the cookie, and has to: the response is
  # cached for a year, and a cache key that does not name the hue serves a reader who
  # changes style the old style's pixels. The cookie stands in for a link written before
  # the parameter existed.
  def text
    theme = Themes.resolve(params[:s].presence || cookies[:theme])
    # c=1 keeps the label's own case, for prose; q=1 is the quiet size and dim tone, for
    # the attribution lines; l=1 is a link and e=1 a heading, drawn in the palette's link
    # and emphasis colours; g=1 is a standing offer (the gamebooks' provisions) in the
    # palette's good colour and r=1 a barred line in its error colour — every style
    # writes some of these in colours of its own, and a colour baked into the image has
    # to be named in the URL the cache is keyed by. Anything else is a label in the body
    # ink, set in capitals.
    quiet = params[:q] == '1'
    keep_case = params[:c] == '1'
    role = role_param

    # Cached on our side as well as at the proxy: the fixed labels — menu entries, section
    # names, headings — are the same picture on every page that carries them, so they are
    # built once and served from memory of it after. Keyed by a digest, since the text runs
    # to a fat paragraph.
    body = Rails.cache.fetch(glyph_cache_key(theme, quiet, keep_case, role), expires_in: 1.week) do
      palette = Themes.palette(theme)
      renderer = CHARSETS[theme]
      if renderer
        lines = renderer.lines(params[:t], keep_case: keep_case, quiet: quiet)
        charset_svg(renderer, lines, palette, quiet: quiet, role: role)
      else
        lines = PhosphorGlyph.lines(params[:t], keep_case: keep_case, quiet: quiet)
        phosphor_svg(lines, palette, quiet: quiet, role: role)
      end
    end

    expires_in 1.year, public: true
    render plain: body, content_type: 'image/svg+xml'
  end

  # Each flag with the palette role it picks, checked in this order: the good and error
  # roles outrank link and emphasis, so a provision drawn inside a button stays in the
  # good colour rather than the link's.
  ROLES = { g: :good, r: :error, l: :link, e: :emphasis }.freeze

  private

  def role_param
    ROLES.find { |flag, _| params[flag] == '1' }&.last || :ink
  end

  def glyph_cache_key(theme, quiet, keep_case, role)
    ['glyph', theme, quiet, keep_case, role, Digest::SHA256.hexdigest(params[:t].to_s)]
  end

  # The phosphor styles write their links and headings in the body colour — one hue is
  # the whole conceit — but the good and error roles keep their own: a green screen's
  # provisions come out yellow (see Themes) rather than invisible.
  def phosphor_svg(lines, palette, quiet: false, role: :ink)
    width = PhosphorGlyph.width(lines, quiet: quiet)
    height = PhosphorGlyph.height(lines, quiet: quiet)
    ink = quiet ? palette[:quiet] : palette.fetch(role)
    font = quiet ? PhosphorGlyph::QUIET_FONT_SIZE : PhosphorGlyph::FONT_SIZE
    line_height = quiet ? PhosphorGlyph::QUIET_LINE_HEIGHT : PhosphorGlyph::LINE_HEIGHT

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
      <defs>
      <filter id="g" x="-40%" y="-40%" width="180%" height="180%">
      #{BLUR_RADII.map.with_index { |r, i| %(<feGaussianBlur in="SourceGraphic" stdDeviation="#{r}" result="b#{i}"/>) }.join("\n")}
      <feMerge>#{BLUR_RADII.each_index.to_a.reverse.map { |i| %(<feMergeNode in="b#{i}"/>) }.join}<feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
      <pattern id="s" width="1" height="3" patternUnits="userSpaceOnUse">
      <rect width="1" height="1" fill="#000000" fill-opacity="#{SCAN_OPACITY}"/>
      </pattern>
      </defs>
      <rect width="100%" height="100%" fill="#{palette[:paper]}"/>
      <g font-family="monospace" font-size="#{font}" fill="#{ink}" filter="url(#g)">
      #{text_lines(lines, line_height)}
      </g>
      <rect width="100%" height="100%" fill="url(#s)"/>
      </svg>
    SVG
  end

  # A character set as its original pixels: no glow and no raster — these machines put
  # flat squares on the glass — and no background, so a style that gives its headings a
  # filled block draws that block in CSS and shows it through the unlit pixels. The quiet
  # size takes the dim tone, as everywhere else.
  def charset_svg(renderer, lines, palette, quiet: false, role: :ink)
    width = renderer.width(lines, quiet: quiet)
    height = renderer.height(lines, quiet: quiet)
    ink = quiet ? palette[:quiet] : palette.fetch(role)

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
      <g fill="#{ink}">
      #{renderer.rects(lines, quiet: quiet)}
      </g>
      </svg>
    SVG
  end

  # The text is whatever the page put in a link, so it is escaped, not trusted.
  def text_lines(lines, line_height)
    lines.map.with_index do |line, index|
      y = PhosphorGlyph::PADDING + ((index + 1) * line_height) - 5
      %(<text x="#{PhosphorGlyph::PADDING}" y="#{y}">#{ERB::Util.html_escape(line)}</text>)
    end.join("\n")
  end
end
