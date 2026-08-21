# frozen_string_literal: true

require 'playing_cards'

# A playing card drawn as a tiny SVG, served like the glyphs: Opera's servers rasterise
# it and send pixels, so the handset never needs a font that knows what a heart is —
# the suits are paths, not characters. One card is one URL, cached for a year; 'back'
# is the face-down card the house hides.
class CardController < ApplicationController
  WIDTH = 30
  HEIGHT = 42
  RED = %w[h d].freeze
  INK = { true => '#C0182C', false => '#111111' }.freeze

  # Each suit in a 12x12 box, drawn at the foot of the card.
  SUITS = {
    'h' => '<path d="M6 10.8 C1.2 7.2 0 4.8 0 3.2 C0 1.4 1.4 0 3.2 0 C4.4 0 5.4 0.6 6 1.6 ' \
           'C6.6 0.6 7.6 0 8.8 0 C10.6 0 12 1.4 12 3.2 C12 4.8 10.8 7.2 6 10.8 Z"/>',
    'd' => '<path d="M6 0 L11 6 L6 12 L1 6 Z"/>',
    's' => '<path d="M6 0 C10.8 4 12 6 12 7.8 C12 9.6 10.6 10.6 9 10.6 C7.9 10.6 7 10.2 6.6 9.4 ' \
           'C6.9 10.8 7.4 11.6 8 12 L4 12 C4.6 11.6 5.1 10.8 5.4 9.4 C5 10.2 4.1 10.6 3 10.6 ' \
           'C1.4 10.6 0 9.6 0 7.8 C0 6 1.2 4 6 0 Z"/>',
    'c' => '<circle cx="6" cy="3.2" r="3.1"/><circle cx="2.9" cy="7.4" r="3.1"/>' \
           '<circle cx="9.1" cy="7.4" r="3.1"/>' \
           '<path d="M6 6 C6.4 9.6 7 11 8 12 L4 12 C5 11 5.6 9.6 6 6 Z"/>'
  }.freeze

  def show
    code = params[:code].to_s
    unless PlayingCards::DECK.include?(code) || code == 'back'
      head :not_found
      return
    end

    body = Rails.cache.fetch(['card', code], expires_in: 1.week) do
      code == 'back' ? back_svg : card_svg(code)
    end
    expires_in 1.year, public: true
    render plain: body, content_type: 'image/svg+xml'
  end

  private

  def card_svg(code)
    rank = code[0] == 'T' ? '10' : code[0]
    ink = INK.fetch(RED.include?(code[1]))
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">
      <rect x="0.5" y="0.5" width="#{WIDTH - 1}" height="#{HEIGHT - 1}" rx="3" fill="#ffffff" stroke="#8a8a8a"/>
      <text x="15" y="19" text-anchor="middle" font-family="sans-serif" font-size="16" font-weight="bold" fill="#{ink}">#{rank}</text>
      <g transform="translate(8 23) scale(1.1667)" fill="#{ink}">#{SUITS.fetch(code[1])}</g>
      </svg>
    SVG
  end

  def back_svg
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">
      <rect x="0.5" y="0.5" width="#{WIDTH - 1}" height="#{HEIGHT - 1}" rx="3" fill="#ffffff" stroke="#8a8a8a"/>
      <rect x="3" y="3" width="#{WIDTH - 6}" height="#{HEIGHT - 6}" rx="2" fill="#1E5AA8"/>
      <path d="M3 10 L27 32 M3 18 L27 40 M3 2 L27 24 M27 10 L3 32 M27 18 L3 40 M27 2 L3 24"
            stroke="#ffffff" stroke-opacity="0.55" stroke-width="1" fill="none"/>
      </svg>
    SVG
  end
end
