# frozen_string_literal: true

require 'playing_cards'

# Pontoon against the house: twist or stick, ten on every hand. The whole game rides in
# one cookie — bank, the shuffled shoe, both hands — so a reload changes nothing and the
# next card is the next card, dealt from a shoe shuffled when the hand began.
class PontoonController < ApplicationController
  STAKE = 10
  BANK_AT_THE_START = 100

  def show
    @bank, @phase, @deck, @player, @dealer, @result = state
  end

  def deal
    bank, phase, = state
    return redirect_to games_pontoon_path if phase == 'play' || bank < STAKE

    deck = PlayingCards.shuffled
    player, deck = PlayingCards.deal(deck, 2)
    dealer, deck = PlayingCards.deal(deck, 2)

    if PlayingCards.hand_value(player) == 21
      # A natural settles on the spot and pays half as much again.
      save([bank + STAKE + (STAKE / 2), 'done', deck, player.join, dealer.join, 'natural'])
    else
      save([bank, 'play', deck, player.join, dealer.join, ''])
    end
    redirect_to games_pontoon_path
  end

  def twist
    bank, phase, deck, player, dealer, = state
    return redirect_to games_pontoon_path unless phase == 'play'

    drawn, deck = PlayingCards.deal(deck)
    player += drawn
    total = PlayingCards.hand_value(player)
    if total > 21
      save([bank - STAKE, 'done', deck, player.join, dealer.join, 'bust'])
    elsif total == 21
      # Twenty-one cannot be improved and any card busts it: the hand sticks itself
      # rather than offering a twist nobody should press.
      showdown(bank, deck, player, dealer)
    else
      save([bank, 'play', deck, player.join, dealer.join, ''])
    end
    redirect_to games_pontoon_path
  end

  def stick
    bank, phase, deck, player, dealer, = state
    return redirect_to games_pontoon_path unless phase == 'play'

    showdown(bank, deck, player, dealer)
    redirect_to games_pontoon_path
  end

  # Broke, or just done: back to a fresh bank. The button says which.
  def reset
    cookies.delete('PONTOON')
    redirect_to games_pontoon_path
  end

  private

  # The house has no choices to make: it draws to seventeen and stops, and the hand
  # settles.
  def showdown(bank, deck, player, dealer)
    while PlayingCards.hand_value(dealer) < 17
      drawn, deck = PlayingCards.deal(deck)
      dealer += drawn
    end
    save([settled_bank(bank, player, dealer), 'done', deck, player.join,
          dealer.join, verdict(player, dealer)])
  end

  def settled_bank(bank, player, dealer)
    case verdict(player, dealer)
    when 'won' then bank + STAKE
    when 'lost' then bank - STAKE
    else bank
    end
  end

  def verdict(player, dealer)
    house = PlayingCards.hand_value(dealer)
    mine = PlayingCards.hand_value(player)
    return 'won' if house > 21 || mine > house
    return 'push' if mine == house

    'lost'
  end

  def save(parts)
    cookies.permanent['PONTOON'] = parts.join('|')
  end

  def state
    bank, phase, deck, player, dealer, result = cookies['PONTOON'].to_s.split('|')
    bank = bank.to_s.match?(/\A-?\d+\z/) ? bank.to_i : BANK_AT_THE_START
    [bank, phase.to_s, deck.to_s, player.to_s.scan(/../), dealer.to_s.scan(/../),
     result.to_s]
  end
end
