# frozen_string_literal: true

# A pack of cards for the games that deal one: each card two characters, rank then
# suit, and a whole deck a 104-character string that fits in a cookie — which is what
# stops a reload from reshuffling fate.
module PlayingCards
  RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
  SUITS = %w[s h d c].freeze
  DECK = RANKS.product(SUITS).map(&:join).freeze
  SUIT_NAMES = { 's' => 'spades', 'h' => 'hearts', 'd' => 'diamonds', 'c' => 'clubs' }.freeze
  RANK_NAMES = { 'T' => '10', 'J' => 'Jack', 'Q' => 'Queen', 'K' => 'King', 'A' => 'Ace' }.freeze

  def self.shuffled
    DECK.shuffle.join
  end

  def self.deal(deck, count = 1)
    [deck[0, count * 2].scan(/../), deck[(count * 2)..]]
  end

  # "Qh" -> "Q♥h"-free plain text a 240px screen and an uncertain charset can carry.
  def self.show(card)
    "#{RANK_NAMES.fetch(card[0], card[0])}#{card[1]}"
  end

  def self.name(card)
    rank = RANK_NAMES.fetch(card[0], card[0])
    "#{rank} of #{SUIT_NAMES[card[1]]}"
  end

  def self.rank_index(card)
    RANKS.index(card[0])
  end

  # Pontoon value: aces are eleven until that busts the hand, then one apiece.
  def self.hand_value(cards)
    values = cards.map { |card| card_value(card[0]) }
    total = values.sum
    aces = cards.count { |card| card[0] == 'A' }
    while total > 21 && aces.positive?
      total -= 10
      aces -= 1
    end
    total
  end

  def self.card_value(rank)
    return 11 if rank == 'A'
    return 10 if %w[T J Q K].include?(rank)

    rank.to_i
  end
end
