# frozen_string_literal: true

require 'phosphor_glyph'

# The shared engine for text drawn from a character generator ROM: fixed-size cells of
# bits, rendered into SVG as filled rectangles. C64Glyph and TeletextGlyph extend this and
# state what differs — the cell size, the sizes it is drawn at, the charset, and whether
# the machine had a lower case.
#
# No font can reach the handset any other way: Opera Mini renders with the device font
# alone and ignores any face a page names. What its servers do carry faithfully is images,
# so the characters travel as their original bitmaps and arrive as finished pixels.
#
# The SVG carries no background: the page behind a glyph is already the theme's ground,
# and a style that gives its headings a filled block draws that block in CSS and shows it
# through the glyph's unlit pixels.
module CellGlyph
  MAX_TEXT = PhosphorGlyph::MAX_TEXT

  # Typographic marks folded to characters these machines had. Anything still outside a
  # charset after this becomes '?', which is honest about what the screen cannot show.
  SUBSTITUTIONS = { '’' => "'", '‘' => "'", '‚' => "'", '`' => "'", '´' => "'",
                    '“' => '"', '”' => '"', '„' => '"',
                    '–' => '-', '—' => '-', '−' => '-', '_' => '-', '…' => '...' }.freeze

  # Wrapped exactly as the phosphor glyphs wrap, to the column this cell width allows.
  # Labels are set in capitals as everywhere else; keep_case is honoured only by a machine
  # that has a lower case to keep.
  def lines(text, keep_case: false, quiet: false)
    text = text.to_s[0, MAX_TEXT]
    text = text.upcase unless keep_case && self::CASED
    max = quiet ? self::QUIET_MAX_CHARS : self::MAX_CHARS

    normalise(text).split("\n", -1).flat_map { |row| PhosphorGlyph.wrap(row, max) }
                   .presence || ['']
  end

  # Accents folded onto their base letters, typographic marks onto the plain ones, and
  # whatever remains unknown shown as '?'. Newlines pass through: they are how a screen of
  # rows travels as one glyph.
  def normalise(text)
    text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').each_char.map do |char|
      next char if char == "\n"

      SUBSTITUTIONS.fetch(char, char).each_char.map do |piece|
        charset(piece) ? piece : '?'
      end.join
    end.join
  end

  def width(lines, quiet: false)
    (self::PADDING * 2) + (lines.map(&:length).max * (quiet ? self::QUIET_CHAR_WIDTH : self::CHAR_WIDTH))
  end

  def height(lines, quiet: false)
    (self::PADDING * 2) + (lines.length * (quiet ? self::QUIET_LINE_HEIGHT : self::LINE_HEIGHT))
  end

  # The lit pixels of every character, as SVG rectangles. Rows of a glyph that repeat —
  # the stems of an H, the bars of an M — are merged into one taller rectangle, and runs
  # of lit bits within a row into one wider one, which keeps the SVG a fraction of the
  # size of one rectangle per pixel. Only geometry leaves here: the text has already been
  # reduced to charset lookups, so nothing user-written reaches the markup.
  #
  # Square pixels at the cell's scale; the line advance is separate, so any room it has
  # over the cell becomes the gap between rows rather than a stretch of the glyphs.
  def rects(lines, quiet: false)
    scale = (quiet ? self::QUIET_CHAR_WIDTH : self::CHAR_WIDTH) / self::CELL_WIDTH.to_f
    advance = quiet ? self::QUIET_LINE_HEIGHT : self::LINE_HEIGHT

    lines.each_with_index.flat_map do |line, row_index|
      line.each_char.with_index.flat_map do |char, column|
        runs(charset(char) || []).map do |top, left, width, depth|
          x = self::PADDING + (((column * self::CELL_WIDTH) + left) * scale)
          y = self::PADDING + (row_index * advance) + (top * scale)
          %(<rect x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(width * scale)}" height="#{fmt(depth * scale)}"/>)
        end
      end
    end.join("\n")
  end

  # The horizontal runs of lit bits in a bitmap, each with the count of identical rows
  # beneath it, as [top, left, width, depth].
  def runs(bitmap)
    found = []
    row = 0
    while row < bitmap.length
      depth = 1
      depth += 1 while row + depth < bitmap.length && bitmap[row + depth] == bitmap[row]
      row_runs(bitmap[row]).each { |left, width| found << [row, left, width, depth] }
      row += depth
    end
    found
  end

  # The runs of lit bits in one row, left to right, as [left, width]. The scan runs one
  # bit past the cell so a run against the right edge still closes.
  def row_runs(bits)
    found = []
    left = nil
    (0..self::CELL_WIDTH).each do |bit|
      if bit < self::CELL_WIDTH && bits[self::CELL_WIDTH - 1 - bit] == 1
        left ||= bit
      elsif left
        found << [left, bit - left]
        left = nil
      end
    end
    found
  end

  def fmt(value)
    (value % 1).zero? ? value.to_i : value.round(2)
  end
end
