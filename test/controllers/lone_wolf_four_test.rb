# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# The Chasm of Doom: carry-over from whichever earlier book was finished, an armoury
# that lets you take six things, and the mechanics this book adds — a disadvantage
# that lasts only the first rounds, lungs that burn underwater, and a horseman whose
# charge carries him past after one exchange.
class LoneWolfFourTest < ActionDispatch::IntegrationTest
  BOOK = 'the-chasm-of-doom'
  KALTE_VETERAN = '350|skill:20,endurance:28,endurance_max:30,gold:40,gold_max:50|' \
                  'camouflage,hunting,sixth sense,tracking,mindshield,healing,' \
                  'weaponskill in sword,sommerswerd,sword,meal:2,firesphere|'

  # The armoury sits one page past the new-discipline lesson.
  ARMOURY_CHOICE = 1

  def pack(section, stats: 'skill:18,endurance:26,endurance_max:26,gold:20,gold_max:50',
           items: 'sword', fight: '')
    cookies['CYOA'] = { BOOK => "#{section}|#{stats}|#{items}|#{fight}" }.to_json
  end

  def entry = JSON.parse(cookies['CYOA'])[BOOK]

  def landing
    query = Rack::Utils.parse_query(URI(@response.headers['Location']).query.to_s)
    [URI(@response.headers['Location']).path, query]
  end

  def stats_of(packed)
    packed.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }
  end

  test 'the fourth book is on the series page under its own volume' do
    get '/games/series/lone-wolf'
    assert_match 'Book Four - The Chasm of Doom', @response.body
  end

  test 'a kai lord out of kalte rides south with everything and an eighth discipline' do
    cookies['CYOA'] = { 'the-caverns-of-kalte' => KALTE_VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    assert_redirected_to "/games/#{BOOK}/armoury"
    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_equal 20, rolled['skill']
    assert_equal [28, 28], [rolled['endurance'], rolled['endurance_max']],
                 'the current score carries, and is the new ceiling'
    assert_equal 50, rolled['gold'], 'forty carried plus a fresh purse, pouch-capped'

    held = items.split(',')
    assert_includes held, 'sommerswerd'
    assert_includes held, 'firesphere', 'the Kalte Firesphere lights this book too'
    assert_includes held, 'badge of rank'
    assert_includes held, 'map of the southlands'
    assert_includes held, 'armoury choice:6'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    skills = held.count { |i| draw.include?(i) || i.start_with?('weaponskill in ') }
    assert_equal 7, skills, 'the seven carried over'
    assert_includes held, 'discipline choice:1', 'the eighth is the reader\'s to choose'
  end

  test 'finishing only the first book still carries that kai lord south' do
    cookies['CYOA'] = {
      'flight-from-the-dark' => '350|skill:16,endurance:24,endurance_max:24,gold:8,gold_max:50|' \
                                'camouflage,healing,sixth sense,tracking,mindblast,axe|'
    }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    rolled = stats_of(entry.split('|')[1])
    assert_equal 16, rolled['skill'], 'the earliest finished book is the fallback'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    held = entry.split('|')[2].split(',')
    skills = held.count { |i| draw.include?(i) || i.start_with?('weaponskill in ') }
    assert_equal 5, skills, 'the five carried over'
    assert_includes held, 'discipline choice:1', 'and one more to choose'
  end

  test 'the armoury allows six picks and no more' do
    pack 'armoury', items: 'armoury choice:6'

    %w[warhammer dagger sword spear mace shield].each do |item|
      post '/games/take', params: { book: BOOK, item: item }
    end
    held = entry.split('|')[2].split(',')
    assert_no_match(/armoury choice/, entry, 'all six spent')
    assert_includes held, 'shield'

    get "/games/#{BOOK}/armoury"
    assert_no_match(/Five Special Rations/, @response.body, 'nothing left to spend')
    post '/games/take', params: { book: BOOK, item: 'chainmail waistcoat' }
    assert_not_includes entry.split('|')[2].split(','), 'chainmail waistcoat'
  end

  # Section 62: "Deduct 2 from your COMBAT SKILL for the first 3 rounds of combat, as
  # you are now lying on the ground."
  test 'a disadvantage that lasts three rounds ends on the fourth' do
    kit = 'skill:18,endurance:40,endurance_max:40,gold:5,gold_max:50'
    pack '62', stats: kit, items: 'sword'
    get "/games/#{BOOK}/62"
    assert_match 'Attack ratio -1.', @response.body, 'eighteen against seventeen, less two'

    pack '62', stats: kit, items: 'sword', fight: '0:20:3:0:40'
    get "/games/#{BOOK}/62"
    assert_match 'Attack ratio +1.', @response.body, 'on your feet again by the fourth round'
  end

  # Section 234: the Meresquid drags you under. How long the reader can hold their
  # breath is thrown once as the fight starts and rides in the fight itself, so a
  # reload cannot re-roll it; once it runs out every round costs air as well as blood.
  test 'a fight held underwater starts costing breath once the throw runs out' do
    kit = 'skill:16,endurance:60,endurance_max:60,gold:5,gold_max:50'

    # A fresh plunge throws the breath: one to ten rounds, two more with the discipline.
    pack '234', stats: kit, items: 'sword'
    post '/games/turn', params: { book: BOOK, from: '234', choice: 'fight' }
    assert_includes 1..10, entry.split('|', 4).last.split(':').last.to_i,
                    'the breath is thrown as the water closes over'

    pack '234', stats: kit, items: 'sword,mind over matter'
    post '/games/turn', params: { book: BOOK, from: '234', choice: 'fight' }
    assert_includes 3..12, entry.split('|', 4).last.split(':').last.to_i,
                    'Mind Over Matter buys two rounds more'

    # Inside the breath: only the blade tells.
    pack '234', stats: kit, items: 'sword', fight: '0:30:2:0:60:5'
    post '/games/turn', params: { book: BOOK, from: '234', choice: 'fight' }
    _, early = landing
    assert_equal LoneWolf.strike(0, early['rn'].to_i).last, early['you'].to_i,
                 'early rounds cost only what the table says'

    # Past it: two more every round, for want of air.
    pack '234', stats: kit, items: 'sword', fight: '0:30:6:0:60:5'
    post '/games/turn', params: { book: BOOK, from: '234', choice: 'fight' }
    _, late = landing
    assert_equal LoneWolf.strike(0, late['rn'].to_i).last + 2, late['you'].to_i,
                 'later rounds cost two more for want of air'
  end

  # Section 333: a horseman at the charge, one exchange, then he is past.
  test 'the charging horseman is decided in a single exchange' do
    pack '333', stats: 'skill:18,endurance:40,endurance_max:40,gold:5,gold_max:50', items: 'sword'
    post '/games/turn', params: { book: BOOK, from: '333', choice: 'fight' }

    path, = landing
    assert_includes %w[209 220 344].map { |id| "/games/#{BOOK}/#{id}" }, path
    assert_match(/^(209|220|344)\|/, entry, 'the charge does not become a duel to the death')
  end

  # Section 117: a Torch AND a Tinderbox, or else a Firesphere.
  test 'a gate that wants two things together is satisfied by either route' do
    kit = 'skill:18,endurance:26,endurance_max:26,gold:5,gold_max:50'
    pack '117', stats: kit, items: 'sword,torch'
    get "/games/#{BOOK}/117"
    assert_match(/needs the torch and the tinderbox or the firesphere/, @response.body,
                 'a torch alone will not light the bridge')

    pack '117', stats: kit, items: 'sword,torch,tinderbox'
    get "/games/#{BOOK}/117"
    assert_no_match(/needs the torch/, @response.body, 'both together will')

    pack '117', stats: kit, items: 'sword,firesphere'
    get "/games/#{BOOK}/117"
    assert_no_match(/needs the torch/, @response.body, 'and so will the Firesphere')
  end

  test 'every route in the fourth book leads somewhere real' do
    sections = Gamebooks.find(BOOK)['sections']
    sections.each do |id, section|
      (section['choices'] || []).each do |choice|
        assert sections.key?(choice['to']), "#{id} -> #{choice['to']}" if choice['to']
        assert_pick(sections, choice['pick'], id) if choice['pick']
      end
      assert_combat_routes(sections, section['combat'] || {}, id)
    end
    assert_equal(0, sections.count { |_, sec| sec['rnt'] })
  end

  private

  def assert_pick(sections, pick, where)
    pick['routes'].each do |route|
      landable = route['die'] || route['pick'] || sections.key?(route['to'])
      assert landable, "#{where}: a pick route leads nowhere"
      assert_pick(sections, route['pick'], where) if route['pick']
    end
  end

  def assert_combat_routes(sections, combat, id)
    assert sections.key?(combat['on_wound']), "#{id}: on_wound" if combat['on_wound']
    %w[evade overtime].each do |rule|
      to = combat.dig(rule, 'to')
      assert sections.key?(to), "#{id}: #{rule}" unless to.nil?
    end
    %w[more less same].each do |branch|
      to = combat.dig('duel', branch)
      assert sections.key?(to), "#{id}: duel" unless to.nil?
    end
  end
end
