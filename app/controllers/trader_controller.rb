# frozen_string_literal: true

require 'zlib'

# A tramp steamer between six ports: buy what a port sells cheap, sail, sell dear, and
# stay ahead of the debt compounding at five percent a day. Prices come from a checksum
# of port, day and good rather than from a stored table — the same everywhere and on
# every reload, so there is nothing to reroll and nothing to store beyond the ship.
class TraderController < ApplicationController
  PORTS = %w[London Lisbon Tangier Alexandria Bombay Singapore].freeze
  GOODS = [['Tea', 20, 60], ['Silk', 80, 240], ['Rubber', 15, 45],
           ['Spices', 120, 480]].freeze
  HOLD = 100
  INTEREST = 1.05

  def show
    @day, @port, @cash, @debt, @cargo, @best = state
    @prices = GOODS.each_index.map { |good| price(good, @port, @day) }
  end

  # The harbour board: where to next, each passage priced in days. A pure read.
  def sail
    @day, @port, = state
  end

  def trade
    day, port, cash, debt, cargo, best = state
    good = params[:good].to_i.clamp(0, GOODS.length - 1)
    each = price(good, port, day)

    if params[:op] == 'sell'
      cash += cargo[good] * each
      cargo[good] = 0
    else
      bought = [cash / each, HOLD - cargo.sum].min
      cargo[good] += bought
      cash -= bought * each
    end
    save([day, port, cash, debt, cargo.join(','), best])
    redirect_to games_trader_path
  end

  def go
    day, port, cash, debt, cargo, best = state
    destination = params[:port].to_i.clamp(0, PORTS.length - 1)
    passage = [(destination - port).abs, 1].max
    # The debt compounds once per day at sea, which is what makes long passages a
    # decision rather than a scenery change.
    passage.times { debt = (debt * INTEREST).round }

    save([day + passage, destination, cash, debt, cargo.join(','), best])
    redirect_to games_trader_path
  end

  def pay
    day, port, cash, debt, cargo, best = state
    paid = [cash, debt].min
    save([day, port, cash - paid, debt - paid, cargo.join(','), best])
    redirect_to games_trader_path
  end

  # Ashore for good: the final position becomes the best score if it beats it, and the
  # next ship starts fresh.
  def retire
    day, port, cash, debt, cargo, best = state
    worth = cash - debt + GOODS.each_index.sum { |good| cargo[good] * price(good, port, day) }
    cookies.permanent['TRADER'] = fresh([best, worth].max)
    redirect_to games_trader_path
  end

  private

  def price(good, port, day)
    _, low, high = GOODS[good]
    low + (Zlib.crc32("#{good}:#{port}:#{day}") % (high - low))
  end

  def save(parts)
    cookies.permanent['TRADER'] = parts.join('|')
  end

  def fresh(best = 0)
    [1, 0, 500, 500, Array.new(GOODS.length, 0).join(','), best].join('|')
  end

  def state
    parts = cookies['TRADER'].to_s.split('|')
    parts = fresh.split('|') unless parts.length == 6
    cargo = parts[4].split(',').map(&:to_i)
    cargo = Array.new(GOODS.length, 0) unless cargo.length == GOODS.length
    [parts[0].to_i, parts[1].to_i.clamp(0, PORTS.length - 1), parts[2].to_i,
     parts[3].to_i, cargo, parts[5].to_i]
  end
end
