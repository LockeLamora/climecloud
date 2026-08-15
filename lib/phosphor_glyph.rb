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
  # wide, and 23 of them plus the padding is 215px.
  FONT_SIZE = 15
  CHAR_WIDTH = 9
  LINE_HEIGHT = 19
  PADDING = 4
  MAX_CHARS = 23
  # Long enough for any label or headline; a crawler feeding the endpoint a novel gets it
  # cut, not rendered.
  MAX_TEXT = 240

  # Words wrapped to the column, the way the browser would wrap the text this replaces.
  # A word longer than a line is split rather than overflowing: an image wider than the
  # screen costs the handset its single-column reflow.
  #
  # Labels and headings are set in capitals, the way the terminals these styles borrow from
  # set theirs; prose keeps its case, because a whole article in capitals is a wall.
  def self.lines(text, keep_case: false)
    text = text.to_s[0, MAX_TEXT]
    words = (keep_case ? text : text.upcase).split
    words = [''] if words.empty?

    words.each_with_object([]) do |word, lines|
      word.scan(/.{1,#{MAX_CHARS}}/).each do |piece|
        if lines.any? && "#{lines.last} #{piece}".length <= MAX_CHARS
          lines[-1] = "#{lines.last} #{piece}"
        else
          lines << piece
        end
      end
    end
  end

  def self.width(lines)
    (PADDING * 2) + (lines.map(&:length).max * CHAR_WIDTH)
  end

  def self.height(lines)
    (PADDING * 2) + (lines.length * LINE_HEIGHT)
  end
end
