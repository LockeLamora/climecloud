# frozen_string_literal: true

require 'phosphor_glyph'
require 'themes'

# Text drawn as a phosphor screen, served as SVG. See PhosphorGlyph for why the glow has to
# travel inside an image: this is the one form in which blur, alpha and compositing reach
# the handset, because Opera's servers rasterise the SVG and send pixels.
class PhosphorController < ApplicationController
  # The bloom, per style: the hue at three radii, echoing the treatment a compositing
  # browser draws over the page text — a tight ring, the glow, and the wide spill.
  BLUR_RADII = [0.6, 2.5, 6].freeze
  # The raster: one line in three, at the depth the page-wide treatment uses.
  SCAN_OPACITY = 0.32

  # The theme comes in the URL rather than off the cookie, and has to: the response is
  # cached for a year, and a cache key that does not name the hue serves a reader who
  # changes style the old style's pixels until the cache expires. The cookie stands in for
  # a link written before the parameter existed.
  def text
    theme = Themes.resolve(params[:s].presence || cookies[:theme])
    # c=1 keeps the label's own case, for prose; anything else is set in capitals.
    lines = PhosphorGlyph.lines(params[:t], keep_case: params[:c] == '1')

    expires_in 1.year, public: true
    render plain: svg(lines, Themes.palette(theme)), content_type: 'image/svg+xml'
  end

  private

  def svg(lines, palette)
    width = PhosphorGlyph.width(lines)
    height = PhosphorGlyph.height(lines)

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
      <g font-family="monospace" font-size="#{PhosphorGlyph::FONT_SIZE}" fill="#{palette[:ink]}" filter="url(#g)">
      #{text_lines(lines)}
      </g>
      <rect width="100%" height="100%" fill="url(#s)"/>
      </svg>
    SVG
  end

  # The text is whatever the page put in a link, so it is escaped, not trusted.
  def text_lines(lines)
    lines.map.with_index do |line, index|
      y = PhosphorGlyph::PADDING + ((index + 1) * PhosphorGlyph::LINE_HEIGHT) - 5
      %(<text x="#{PhosphorGlyph::PADDING}" y="#{y}">#{ERB::Util.html_escape(line)}</text>)
    end.join("\n")
  end
end
