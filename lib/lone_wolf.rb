# frozen_string_literal: true

# The Lone Wolf combat rules, as published by Project Aon and used here with their
# blessing. One strike: the combat ratio picks a column, the random number a row, and
# the cell says what each side loses. 99 stands for the table's K — killed outright.
module LoneWolf
  KILLED = 99

  # Columns are the ratio bands -11-or-less through 11-or-greater; rows are the random
  # numbers 0-9. Transcribed from the tables in the book's Project Aon edition.
  ENEMY_LOSS = {
    0 => [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 99, 99, 99],
    1 => [0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    2 => [0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    3 => [0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    4 => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    5 => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14],
    6 => [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16],
    7 => [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18],
    8 => [4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 99],
    9 => [5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 99, 99]
  }.freeze

  WOLF_LOSS = {
    0 => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    1 => [99, 99, 8, 6, 6, 5, 5, 5, 4, 4, 4, 3, 3],
    2 => [99, 8, 7, 6, 5, 5, 4, 4, 3, 3, 3, 3, 2],
    3 => [8, 7, 6, 5, 5, 4, 4, 3, 3, 3, 2, 2, 2],
    4 => [8, 7, 6, 5, 4, 4, 3, 3, 2, 2, 2, 2, 2],
    5 => [7, 6, 5, 4, 4, 3, 2, 2, 2, 2, 2, 2, 1],
    6 => [6, 6, 5, 4, 3, 2, 2, 2, 1, 1, 1, 1, 1],
    7 => [5, 5, 4, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0],
    8 => [4, 4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0],
    9 => [3, 3, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  }.freeze

  # The band the ratio falls in: everything at or past eleven either way saturates.
  def self.column(ratio)
    return 0 if ratio <= -11
    return 12 if ratio >= 11
    return 6 if ratio.zero?

    ratio.negative? ? 6 - ((ratio.abs + 1) / 2) : 6 + ((ratio + 1) / 2)
  end

  def self.strike(ratio, random_number)
    band = column(ratio)
    [ENEMY_LOSS.fetch(random_number)[band], WOLF_LOSS.fetch(random_number)[band]]
  end
end
