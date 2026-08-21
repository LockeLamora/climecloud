# frozen_string_literal: true

# The gamebooks' dice: expressions like '2d6', '1d6+6' or a bare '10', rolled with
# real randomness — a page turn is a POST, so a roll happens once per press and a
# reload of the page it landed on changes nothing.
module Dice
  EXPRESSION = /\A(?:(\d+)d(\d+))?([+-]\d+|\d+)?\z/

  def self.roll(expression)
    count, sides, flat = expression.to_s.match(EXPRESSION)&.captures
    total = flat.to_i
    count.to_i.times { total += rand(1..sides.to_i) } if sides
    total
  end
end
