# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

# The sword of the sun is the whole point of Book Two, and every book after it asks
# whether you are carrying one. This walks the actual road: earn it at Hammerdal,
# finish Book Two, open Book Three, and stand in front of the door that asks for it.
class SommerswerdCarryTest < ActionDispatch::IntegrationTest
  TWO = 'fire-on-the-water'
  THREE = 'the-caverns-of-kalte'
  STATS = 'skill:17,endurance:24,endurance_max:26,gold:30,gold_max:50'
  KIT = 'camouflage,hunting,sixth sense,tracking,weaponskill in sword,sword,' \
        'meal:2,seal of hammerdal'

  def cookie
    JSON.parse(cookies['CYOA'])
  end

  def items_in(id)
    cookie[id].split('|')[2].split(',')
  end

  test 'the sword earned at hammerdal is still in hand at the caverns of kalte' do
    # King Alin hands it over in exchange for the Seal: a page's effects land as the
    # reader arrives, so the grant happens on the turn out of 9 and into 196.
    cookies['CYOA'] = { TWO => "9|#{STATS}|#{KIT}|" }.to_json
    post '/games/turn', params: { book: TWO, from: '9', choice: 0 }
    assert_redirected_to(%r{#{TWO}/196})
    assert_includes items_in(TWO), 'sommerswerd', 'Book Two grants it at 196'
    assert_not_includes items_in(TWO), 'seal of hammerdal', 'and takes the Seal for it'

    # Carry that same satchel to Book Two's last page and walk into Book Three.
    earned = cookie[TWO].split('|')[2]
    cookies['CYOA'] = { TWO => "350|#{STATS}|#{earned}|" }.to_json
    post '/games/turn', params: { book: THREE, from: 'start', choice: 1 }
    assert_includes items_in(THREE), 'sommerswerd', 'and it crosses into Book Three'

    # The door at 173 that asks for it must open.
    carried = cookie[THREE].split('|')[2]
    cookies['CYOA'] = { THREE => "173|#{STATS}|#{carried}|" }.to_json
    get "/games/#{THREE}/173"
    assert_response :success
    assert_no_match(/needs the sommerswerd/, @response.body,
                    'the reader is carrying one, so nothing is barred')
    post '/games/turn', params: { book: THREE, from: '173', choice: 1 }
    assert_redirected_to "/games/#{THREE}/164", 'the Sommerswerd branch is theirs'
  end

  # The situation a reader actually lands in: they took a turn in Book Three before
  # finishing Book Two, so a fresh Kai Lord was rolled, and no later finish can reach
  # back into a game already begun. The title page must say so rather than leave them
  # wondering where the Sommerswerd went.
  test 'a fresh character in a sequel is told a veteran is waiting to cross' do
    fresh = 'camouflage,hunting,sixth sense,tracking,healing,sword,map of kalte'
    cookies['CYOA'] = { TWO => "350|#{STATS}|#{KIT},sommerswerd|",
                        THREE => "200|#{STATS}|#{fresh}|" }.to_json

    get "/games/#{THREE}"
    assert_response :success
    assert_match 'Fire on the Water', @response.body,
                 'the title page names the book the veteran is standing in'
    assert_match(/rolled fresh/, @response.body)

    # Starting again brings them across, sword and all.
    post '/games/restart', params: { book: THREE }
    post '/games/turn', params: { book: THREE, from: 'start', choice: 1 }
    assert_includes items_in(THREE), 'sommerswerd'
    assert_includes items_in(THREE), 'carried from fire-on-the-water'
  end

  test 'a kai lord who did cross over is not nagged to do it again' do
    cookies['CYOA'] = { TWO => "350|#{STATS}|#{KIT},sommerswerd|" }.to_json
    post '/games/turn', params: { book: THREE, from: 'start', choice: 1 }
    carried = cookie[THREE].split('|')[2]
    cookies['CYOA'] = { TWO => "350|#{STATS}|#{KIT},sommerswerd|",
                        THREE => "200|#{STATS}|#{carried}|" }.to_json

    get "/games/#{THREE}"
    assert_no_match(/rolled fresh/, @response.body)
  end

  # Every road through Book Two that can reach its last page must still have the sword
  # in hand: nothing between Hammerdal and Holmgard may quietly take it.
  test 'no page of book two strips the sommerswerd from a reader who earned it' do
    book = Gamebooks.find(TWO)
    thieves = book['sections'].filter_map do |id, section|
      fx = ([section['effects']] + Array(section['choices']).map { |c| c['effects'] }).compact
      loses = fx.any? do |f|
        f['drop_specials'] || Array(f['drop']).include?('sommerswerd') || f['impound']
      end
      next unless loses

      # 194 is the robbery at Ragadorn, and it happens before Hammerdal: the text says
      # so itself — "you must find the Seal if you are to persuade the Durenese to give
      # you the Sommerswerd".
      id unless id == '194'
    end
    assert_empty thieves, "these pages take the sword away: #{thieves.inspect}"
  end
end
