# frozen_string_literal: true

require 'playing_cards'

# Higher or Lower: one card showing, call the next one. The cookie carries the card on
# the table, the streak and the best streak, so the game survives between visits like
# everything else here — client side, nothing stored on the server.
class HiloController < ApplicationController
  def show
    @card, @streak, @best = state
  end

  # The guess is a POST like every other move in the games section: a browser that
  # fetches links ahead of the cursor must not play the hand. Ties push — the card
  # changes, the streak stands.
  def guess
    card, streak, best = state
    drawn = (PlayingCards::DECK - [card]).sample
    streak = settle(params[:call], card, drawn, streak)
    best = [best, streak].max

    cookies.permanent['HILO'] = "#{drawn} #{streak} #{best}"
    redirect_to games_hilo_path
  end

  private

  def settle(call, card, drawn, streak)
    was = PlayingCards.rank_index(card)
    now = PlayingCards.rank_index(drawn)
    return streak if now == was
    return streak + 1 if (call == 'higher') == (now > was)

    0
  end

  def state
    card, streak, best = cookies['HILO'].to_s.split
    card = PlayingCards::DECK.sample unless PlayingCards::DECK.include?(card)
    [card, streak.to_i, best.to_i]
  end
end
