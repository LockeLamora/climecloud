# frozen_string_literal: true

# The geometry of a piece of text drawn as a phosphor screen, shared by the controller that
# renders the SVG and the helper that sizes the <img> holding it.
#
# The phosphor styles cannot glow as text: OBML has no shadow primitive, so a text-shadow
# reaches the handset as a filled band behind each text run, and gradients and alpha are
# disabled on Opera's servers outright. What those servers do carry faithfully is images —
# and SVG is on Opera Mini's own list of supported image formats, rasterised server-side
# where blur, alpha and compositing all work. So the glow travels inside the image: the text
# is drawn into an SVG with the bloom and the raster baked in, and the phone receives
# finished pixels.
module PhosphorGlyph
  # Sized for the 240px screen the app is built around: a 15px monospace glyph is about 9px
  # wide, and 23 of them plus the padding is 215px. A narrower screen wraps the images the
  # way it wraps anything; nothing else here assumes a width.
  FONT_SIZE = 15
  CHAR_WIDTH = 9
  LINE_HEIGHT = 19
  PADDING = 4
  MAX_CHARS = 23

  # The quiet size, for the attribution lines: drawn in the palette's dim tone at the scale
  # the .credit style keeps them, so a licence line does not compete with the times above it.
  QUIET_FONT_SIZE = 11
  QUIET_CHAR_WIDTH = 7
  QUIET_LINE_HEIGHT = 14
  QUIET_MAX_CHARS = 30
  # Long enough for a fat paragraph; a crawler feeding the endpoint a novel gets it cut,
  # not rendered. The ceiling matters at the other end too: every glyph is a request
  # Opera's proxy makes and an SVG it rasterises before the page ships, and a page that
  # takes too long to assemble is reported as one that could not be opened. Bigger chunks
  # mean fewer of them.
  MAX_TEXT = 1400

  # Words wrapped to the column, the way the browser would wrap the text this replaces,
  # with a newline in the text starting a fresh line — which is how a table travels as one
  # glyph: each row a line, the columns aligned by the monospace itself.
  #
  # A word longer than a line is split rather than overflowing: an image wider than the
  # screen costs the handset its single-column reflow.
  #
  # Labels and headings are set in capitals, the way the terminals these styles borrow from
  # set theirs; prose keeps its case, because a whole article in capitals is a wall.
  def self.lines(text, keep_case: false, quiet: false)
    text = text.to_s[0, MAX_TEXT]
    text = text.upcase unless keep_case
    max = quiet ? QUIET_MAX_CHARS : MAX_CHARS

    text.split("\n", -1).flat_map { |row| wrap(row, max) }.presence || ['']
  end

  def self.wrap(row, max)
    words = row.split
    return [''] if words.empty?

    words.each_with_object([]) do |word, lines|
      word.scan(/.{1,#{max}}/).each do |piece|
        if lines.any? && "#{lines.last} #{piece}".length <= max
          lines[-1] = "#{lines.last} #{piece}"
        else
          lines << piece
        end
      end
    end
  end

  def self.width(lines, quiet: false)
    (PADDING * 2) + (lines.map(&:length).max * (quiet ? QUIET_CHAR_WIDTH : CHAR_WIDTH))
  end

  def self.height(lines, quiet: false)
    (PADDING * 2) + (lines.length * (quiet ? QUIET_LINE_HEIGHT : LINE_HEIGHT))
  end
end
