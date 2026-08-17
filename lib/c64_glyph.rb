# frozen_string_literal: true

require 'c64_charset'
require 'cell_glyph'

# The geometry of text drawn in the C64's own character set, shared by the controller that
# renders the SVG and the helper that sizes the <img> holding it. The engine is CellGlyph;
# what is stated here is the machine.
module C64Glyph
  extend CellGlyph

  # An 8x8 cell, drawn at 9px so 23 of them — the same line the phosphor screens hold, so
  # a forecast row that fits there fits here — sit inside the 212px the C64 frame leaves
  # of a 240px screen. The line advance takes one pixel more than the cell, which opens
  # the rows a touch the way a TV's scan gaps did.
  CELL_WIDTH = 8
  CHAR_WIDTH = 9
  LINE_HEIGHT = 10
  PADDING = 2
  MAX_CHARS = 23

  # The quiet size, for the attribution lines: the cell at its own 8px, in the dim tone.
  QUIET_CHAR_WIDTH = 8
  QUIET_LINE_HEIGHT = 8
  QUIET_MAX_CHARS = 25

  # The machine's default screen had no lower case, so none is kept.
  CASED = false

  def self.charset(char)
    C64Charset.rows(char)
  end
end
