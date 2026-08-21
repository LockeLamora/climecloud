# frozen_string_literal: true

require 'test_helper'
require 'playing_cards'
require 'riddles'
require 'zlib'

# The little games share their rules: every view is a pure read, every move a POST
# that redirects back to it, and each game's whole state rides in one small cookie.
# Nothing here ever reaches outward, which WebMock enforces across the suite.
class MinigamesTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  test 'every game page renders as a pure read that writes nothing' do
    %w[/games/hilo /games/pontoon /games/trader /games/trader/sail
       /games/journey /games/riddle].each do |path|
      get path

      assert_response :success, "#{path} did not render"
      assert_nil @response.headers['Set-Cookie']&.match(/HILO|PONTOON|TRADER|JOURNEY|RIDDLE/),
                 "#{path} wrote state on a read"
    end
  end

  test 'the games shelf lists the little games after the books' do
    get '/games'

    ['Pontoon', 'Tramp Trader', 'Long Haul', 'Riddle', 'Higher'].each do |name|
      assert_match name, @response.body
    end
  end

  # Higher or Lower: calling lower on a two can never lengthen the streak — the only
  # kind outcome is another two, which pushes.
  test 'hilo cannot win calling lower from the bottom of the pack' do
    cookies['HILO'] = '2s 7 7'

    post '/games/hilo/guess', params: { call: 'lower' }

    assert_redirected_to '/games/hilo'
    card, streak, best = cookies['HILO'].split
    assert_includes PlayingCards::DECK, card
    assert_includes [0, 7], streak.to_i
    assert_equal 7, best.to_i
  end

  test 'pontoon twisting into a bust costs the stake and ends the hand' do
    cookies['PONTOON'] = '100|play|5h2d|TsTd|9h8c|'

    post '/games/pontoon/twist'

    bank, phase, _deck, player, _dealer, result = cookies['PONTOON'].split('|')
    assert_equal 90, bank.to_i
    assert_equal 'done', phase
    assert_equal 'TsTd5h', player
    assert_equal 'bust', result
  end

  test 'pontoon sticking on twenty beats a house that stands on seventeen' do
    cookies['PONTOON'] = '100|play|5h2d|TsKd|9h8c|'

    post '/games/pontoon/stick'

    bank, phase, _deck, _player, dealer, result = cookies['PONTOON'].split('|')
    assert_equal 110, bank.to_i
    assert_equal 'done', phase
    assert_equal '9h8c', dealer, 'seventeen stands: the house must not draw'
    assert_equal 'won', result
  end

  test 'pontoon deals two hands from a fresh shoe without touching the bank' do
    post '/games/pontoon/deal'

    bank, phase, deck, player, dealer, result = cookies['PONTOON'].split('|')
    assert_equal 2, player.length / 2
    assert_equal 2, dealer.length / 2
    assert_equal 48, deck.length / 2
    if result == 'natural'
      assert_equal 115, bank.to_i
    else
      assert_equal(%w[100 play], [bank, phase])
    end
  end

  test 'the trader buys all the hold or cash allows and the same reload prices' do
    post '/games/trader/trade', params: { good: 0, op: 'buy' }

    day, port, cash, _debt, cargo, = cookies['TRADER'].split('|')
    price = 20 + (Zlib.crc32('0:0:1') % 40)
    bought = [500 / price, 100].min
    assert_equal [1, 0], [day.to_i, port.to_i]
    assert_equal 500 - (bought * price), cash.to_i
    assert_equal bought, cargo.split(',').first.to_i
  end

  test 'a passage costs a day and five percent of the debt for each of them' do
    post '/games/trader/go', params: { port: 3 }

    day, port, _cash, debt, = cookies['TRADER'].split('|')
    assert_equal [4, 3], [day.to_i, port.to_i]
    assert_equal 579, debt.to_i, 'three days compounded stepwise from 500'
  end

  test 'a steady burn on a quiet lane moves the run along' do
    seed = (1..5000).find { |candidate| Zlib.crc32("#{candidate}:1:road") % 100 < 25 }
    cookies['JOURNEY'] = "#{seed}|1|0|40|30|2|10|120|0|"

    post '/games/journey/act', params: { move: 'steady' }

    parts = cookies['JOURNEY'].split('|')
    assert_equal [2, 80, 36, 28], parts[1, 4].map(&:to_i)
  end

  # The dock is the only shop on the lane: alongside, the chandler sells; in the deep
  # dark, the same press is refused out loud.
  test 'the chandler sells only alongside a dock' do
    cookies['JOURNEY'] = '7|3|400|4|10|0|8|120|0|'

    post '/games/journey/act', params: { move: 'buy_petrol' }

    parts = cookies['JOURNEY'].split('|')
    assert_equal [3, 400, 14, 90], [parts[1].to_i, parts[2].to_i, parts[3].to_i, parts[7].to_i]

    cookies['JOURNEY'] = '7|3|200|4|10|0|8|120|0|'
    post '/games/journey/act', params: { move: 'buy_petrol' }

    assert_match(/^!Nothing to buy out here/, cookies['JOURNEY'].split('|')[9])
  end

  # The cash loop: a day's work always pays, so a run can never be stranded by an
  # empty purse — only worn down by the days it costs.
  test 'a dock shift earns scrip and spends the day' do
    cookies['JOURNEY'] = '7|3|400|10|10|0|8|20|0|'

    post '/games/journey/act', params: { move: 'work' }

    parts = cookies['JOURNEY'].split('|')
    assert_equal [4, 400, 45], [parts[1].to_i, parts[2].to_i, parts[7].to_i]
    assert_match(/scrip \+25/, parts[9].to_s)

    cookies['JOURNEY'] = '7|3|200|10|10|0|8|20|0|'
    post '/games/journey/act', params: { move: 'work' }
    assert_match(/^!No dock, no shift/, cookies['JOURNEY'].split('|')[9])
  end

  test 'trawling the drift pays what the checksum says, and only in deep space' do
    cookies['JOURNEY'] = '7|3|200|10|10|0|8|20|0|'

    post '/games/journey/act', params: { move: 'trawl' }

    parts = cookies['JOURNEY'].split('|')
    haul = Zlib.crc32('7:3:trawl')
    case haul % 10
    when 0..2 then assert_equal 10 + 3 + (haul % 4), parts[4].to_i
    when 3..4 then assert_equal 10 + 2 + (haul % 3), parts[3].to_i
    when 5..6 then assert_match(/grave-goods/, parts[9])
    when 7 then assert_equal 7, parts[6].to_i
    when 8 then assert_equal 8, parts[4].to_i
    else assert_equal 4, parts[8].to_i, 'a bad ping calls a cutter down'
    end
    assert_equal 4, parts[1].to_i, 'the trawl spends the day'

    cookies['JOURNEY'] = '7|3|400|10|10|0|8|20|0|'
    post '/games/journey/act', params: { move: 'trawl' }
    assert_match(/^!The dockmaster frowns/, cookies['JOURNEY'].split('|')[9])
  end

  test 'the lane is barred at a crossing and the fee buys the way through' do
    cookies['JOURNEY'] = '7|3|650|40|30|2|10|120|0|'

    post '/games/journey/act', params: { move: 'steady' }
    parts = cookies['JOURNEY'].split('|')
    assert_equal [700, 1], [parts[2].to_i, parts[8].to_i], 'the customs chain bars the lane at 700'

    post '/games/journey/act', params: { move: 'pay' }
    parts = cookies['JOURNEY'].split('|')
    assert_equal [700, 0, 90], [parts[2].to_i, parts[8].to_i, parts[7].to_i]
  end

  test 'a burn that would pass a dock berths there instead' do
    seed = (1..5000).find { |candidate| Zlib.crc32("#{candidate}:1:road") % 100 < 25 }
    cookies['JOURNEY'] = "#{seed}|1|350|40|30|2|10|120|0|"

    post '/games/journey/act', params: { move: 'push' }

    parts = cookies['JOURNEY'].split('|')
    assert_equal 400, parts[2].to_i, 'the Salt Havens catch the ship at 400'
    assert_match(/Salt Havens/, parts[9])
  end

  # A move that cannot happen says so in red rather than doing nothing: the day does
  # not turn, and the note names the shortfall.
  test 'an empty tank refuses the burn out loud without spending the day' do
    cookies['JOURNEY'] = '7|3|500|2|30|2|10|120|0|'

    post '/games/journey/act', params: { move: 'steady' }
    parts = cookies['JOURNEY'].split('|')

    assert_equal [3, 500, 2], [parts[1].to_i, parts[2].to_i, parts[3].to_i],
                 'a refused move must change nothing but the note'
    assert parts[9].start_with?('!'), 'the refusal mark picks the red ink'

    get '/games/journey'
    assert_match(/<span class='error'>The ship stays put/, @response.body)
  end

  test 'an empty purse refuses the chandler out loud' do
    cookies['JOURNEY'] = '7|3|400|10|30|2|10|5|0|'

    post '/games/journey/act', params: { move: 'buy_spare' }

    assert_match(/^!A drive part costs 50 and the purse holds 5/, cookies['JOURNEY'].split('|')[9])
  end

  test 'a boarding party takes its scrip and casts off' do
    cookies['JOURNEY'] = '7|3|500|10|30|2|10|120|4|Grapnels out.'

    get '/games/journey'
    assert_match 'Buy them off', @response.body

    post '/games/journey/act', params: { move: 'pay_off' }
    parts = cookies['JOURNEY'].split('|')

    assert_equal [100, 0], [parts[7].to_i, parts[8].to_i]
    assert_match(/scrip -20/, parts[9])
  end

  test 'an empty galley costs the crew and says so' do
    seed = (1..5000).find { |candidate| Zlib.crc32("#{candidate}:1:road") % 100 < 25 }
    cookies['JOURNEY'] = "#{seed}|1|0|40|1|2|10|120|0|"

    post '/games/journey/act', params: { move: 'steady' }

    parts = cookies['JOURNEY'].split('|')
    assert_equal [0, 8], [parts[4].to_i, parts[6].to_i]
    assert_match(/galley is empty: crew -2/, parts[9].to_s)
  end

  test 'the riddle takes one guess a day and chains the streak overnight' do
    travel_to Time.zone.local(2026, 8, 20, 9) do
      right = Riddles.today(Date.current)[:right]
      post '/games/riddle/answer', params: { pick: right }

      assert_equal "20260820 #{right} 1 1", cookies['RIDDLE']

      # The second thought does not count.
      post '/games/riddle/answer', params: { pick: (right + 1) % 3 }
      assert_equal "20260820 #{right} 1 1", cookies['RIDDLE']
    end

    travel_to Time.zone.local(2026, 8, 21, 9) do
      right = Riddles.today(Date.current)[:right]
      post '/games/riddle/answer', params: { pick: right }

      assert_equal "20260821 #{right} 2 2", cookies['RIDDLE']
    end
  end

  test 'a wrong guess shows the answer and breaks the streak' do
    travel_to Time.zone.local(2026, 8, 20, 9) do
      riddle = Riddles.today(Date.current)
      wrong = (riddle[:right] + 1) % riddle[:a].length
      cookies['RIDDLE'] = '20260819 0 4 6'

      post '/games/riddle/answer', params: { pick: wrong }
      get '/games/riddle'

      assert_match riddle[:a][riddle[:right]], @response.body
      assert_match(/Streak 0 - best 6/, @response.body)
    end
  end
end
