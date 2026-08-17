# frozen_string_literal: true

require 'teletext_charset'
require 'cell_glyph'

# The geometry of text drawn in the SAA5050's character set — the chip that drew Ceefax on
# the television — shared by the controller that renders the SVG and the helper that sizes
# the <img> holding it. The engine is CellGlyph; what is stated here is the machine.
module TeletextGlyph
  extend CellGlyph

  # A 6x10 cell, drawn at one and a half times its size: 9px wide puts the same 23
  # characters to the line as every other glyph screen, and the cell's own blank top and
  # bottom rows keep the lines apart at a matching advance.
  CELL_WIDTH = 6
  CHAR_WIDTH = 9
  LINE_HEIGHT = 15
  PADDING = 2
  MAX_CHARS = 23

  # The quiet size, for the attribution lines: the cell at its own 6px, in the dim tone.
  QUIET_CHAR_WIDTH = 6
  QUIET_LINE_HEIGHT = 10
  QUIET_MAX_CHARS = 30

  # The set has a lower case, so prose that asks to keep its own case keeps it.
  CASED = true

  def self.charset(char)
    TeletextCharset.rows(char)
  end
end
