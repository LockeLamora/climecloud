# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# Fire on the Water: the carry-over from Book One, the Royal Armoury's pick-any-two,
# and the mechanics the second book adds — the Sommerswerd, the Shield, Mindforce
# drains, forced arms, contests and dice-priced gold. Combat assertions recompute the
# Combat Results Table row from the echoed random number, as in WarRigTest.
class LoneWolfTwoTest < ActionDispatch::IntegrationTest
  BOOK = 'fire-on-the-water'
  VETERAN = '350|skill:17,endurance:24,endurance_max:26,gold:30,gold_max:50|' \
            'camouflage,hunting,sixth sense,tracking,weaponskill in sword,sword,' \
            'meal:2,crystal star pendant|'

  def pack(section, stats: 'skill:15,endurance:25,endurance_max:25,gold:10,gold_max:50',
           items: 'sword', fight: '')
    cookies['CYOA'] = { BOOK => "#{section}|#{stats}|#{items}|#{fight}" }.to_json
  end

  def entry
    JSON.parse(cookies['CYOA'])[BOOK]
  end

  def landing
    query = Rack::Utils.parse_query(URI(@response.headers['Location']).query.to_s)
    [URI(@response.headers['Location']).path, query]
  end

  def stats_of(packed)
    packed.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }
  end

  # The armoury sits one page past the lesson; a returning Kai Lord may take either
  # branch off the title page, and this is the index of the equipment one.
  ARMOURY_CHOICE = 1

  test 'a kai lord who finished book one walks in with everything and one new skill' do
    cookies['CYOA'] = { 'flight-from-the-dark' => VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    assert_redirected_to "/games/#{BOOK}/armoury"
    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_equal 17, rolled['skill'], 'the combat skill carries as it stood'
    # "You can carry your current scores of COMBAT SKILL and ENDURANCE points over",
    # and "your ENDURANCE can never rise above the number you started with": no book
    # heals the wounds of the last one, and the score walked in with is the new ceiling.
    assert_equal [24, 24], [rolled['endurance'], rolled['endurance_max']],
                 'the wounded score carries, and becomes the new ceiling'
    assert_includes 40..50, rolled['gold'], 'thirty carried plus a fresh pouch, pouch-capped'

    held = items.split(',')
    %w[sword meal:2].each { |carried| assert_includes held, carried }
    assert_includes held, 'crystal star pendant', 'special items carry'
    assert_includes held, 'seal of hammerdal', 'the King entrusts the Seal'
    assert_includes held, 'armoury choice:2'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    skills = held.count { |item| draw.include?(item) || item.start_with?('weaponskill in ') }
    assert_equal 5, skills, 'the five disciplines carried over'
    assert_includes held, 'discipline choice:1',
                    'the sixth is the reader\'s to choose, not the engine\'s to roll'
  end

  # "You may choose one extra Kai Discipline" — a choice, and the reader makes it.
  test 'the returning kai lord chooses the new discipline rather than being dealt one' do
    cookies['CYOA'] = { 'flight-from-the-dark' => VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }
    assert_redirected_to "/games/#{BOOK}/newskill"

    get "/games/#{BOOK}/newskill"
    assert_response :success
    assert_match 'Healing', @response.body, 'a discipline they lack is offered'
    assert_no_match(/Take the camouflage/, @response.body, 'one they already have is not')

    post '/games/take', params: { book: BOOK, item: 'healing' }
    held = entry.split('|')[2].split(',')
    assert_includes held, 'healing'
    assert_not_includes held, 'discipline choice:1', 'the pick is spent'

    get "/games/#{BOOK}/newskill"
    assert_no_match(/Take the mindblast/, @response.body, 'and no second discipline follows')
  end

  test 'weaponskill is chosen with the weapon it is mastered in' do
    bare = VETERAN.sub('weaponskill in sword,', '')
    cookies['CYOA'] = { 'flight-from-the-dark' => bare }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }
    post '/games/turn', params: { book: BOOK, from: 'newskill', choice: 0 }
    assert_redirected_to "/games/#{BOOK}/weaponmaster"

    post '/games/take', params: { book: BOOK, item: 'weaponskill in axe' }
    held = entry.split('|')[2].split(',')
    assert_includes held, 'weaponskill in axe'

    get "/games/#{BOOK}/weaponmaster"
    assert_no_match(/weaponskill in mace/, @response.body,
                    'one weapon only: the rest close once the pick is spent')
  end

  test 'a fresh kai lord is never offered the returning lord\'s lesson' do
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }
    assert_redirected_to "/games/#{BOOK}/armoury"
    assert_not_includes entry.split('|')[2].split(','), 'discipline choice:1'

    get "/games/#{BOOK}/armoury"
    assert_no_match(/Learn a new Kai Discipline/, @response.body)
  end

  test 'without a finished book one, a fresh kai lord is rolled by the book two rules' do
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_includes 10..19, rolled['skill']
    assert_includes 10..19, rolled['gold'], 'the pouch throw, ten to nineteen'
    held = items.split(',')
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    assert_equal(5, held.count { |item| draw.include?(item) || item.start_with?('weaponskill in ') })
    assert_includes held, 'seal of hammerdal'
  end

  test 'the armoury honours exactly two picks and the waistcoat pays its endurance' do
    pack 'armoury', items: 'armoury choice:2', stats: 'skill:15,endurance:25,endurance_max:25,gold:10,gold_max:50'

    post '/games/take', params: { book: BOOK, item: 'shield' }
    held = entry.split('|')[2].split(',')
    assert_includes held, 'shield'
    assert_includes held, 'armoury choice:1', 'one chit spent'

    post '/games/take', params: { book: BOOK, item: 'chainmail waistcoat' }
    rolled = stats_of(entry.split('|')[1])
    assert_equal [29, 29], [rolled['endurance'], rolled['endurance_max']],
                 'the waistcoat lifts the score and the ceiling'
    assert_no_match(/armoury choice/, entry, 'both chits spent')

    get "/games/#{BOOK}/armoury"
    assert_no_match(/A Sword</, @response.body, 'no chits, no more offers')

    post '/games/take', params: { book: BOOK, item: 'sword' }
    assert_no_match(/(\A|,)sword(,|\|)/, entry.split('|')[2], 'a third pick is refused')
  end

  test 'the sommerswerd counts its own worth and doubles what the undead lose' do
    pack '66', items: 'sommerswerd,weaponskill in sword,mindblast'
    post '/games/turn', params: { book: BOOK, from: '66', choice: 'fight' }

    _, query = landing
    # skill 15 + 10 (skilled sommerswerd) - captain 15 = 10; mindblast blanked.
    table_foe, table_you = LoneWolf.strike(10, query['rn'].to_i)
    expected = table_foe >= LoneWolf::KILLED ? table_foe : table_foe * 2
    assert_equal [expected, table_you], [query['foe'].to_i, query['you'].to_i],
                 'ratio ten, the zombie loses double'
  end

  test 'a shield adds its two while carried' do
    pack '110', items: 'sword,shield'
    post '/games/turn', params: { book: BOOK, from: '110', choice: 'fight' }

    _, query = landing
    want = LoneWolf.strike(2, query['rn'].to_i) # 15 - 15 + 2 shield
    assert_equal want, [query['foe'].to_i, query['you'].to_i]
  end

  test 'the helghast is fought with the magic spear and its mindforce gnaws unshielded minds' do
    pack '332', items: 'magic spear,weaponskill in spear,sword'
    get "/games/#{BOOK}/332"
    assert_match(/Fighting with the magic spear \(skill \+2\)/, @response.body,
                 'the spear is the only thing that bites, and spear-skill counts for it')

    post '/games/turn', params: { book: BOOK, from: '332', choice: 'fight' }
    _, query = landing
    table_foe, table_you = LoneWolf.strike(-4, query['rn'].to_i) # 15 + 2 - 21
    assert_equal [table_foe, table_you + 2], [query['foe'].to_i, query['you'].to_i],
                 'two more endurance to the mindforce each round'

    pack '332', items: 'magic spear,weaponskill in spear,mindshield'
    post '/games/turn', params: { book: BOOK, from: '332', choice: 'fight' }
    _, query = landing
    assert_equal LoneWolf.strike(-4, query['rn'].to_i),
                 [query['foe'].to_i, query['you'].to_i], 'mindshield stops the drain'
  end

  test 'the arm-wrestle is a contest: the loser keeps their life and their strength' do
    pack '276', items: 'sword', stats: 'skill:10,endurance:1,endurance_max:25,gold:10,gold_max:50'

    settled = nil
    30.times do
      post '/games/turn', params: { book: BOOK, from: '276', choice: 'fight' }
      path, = landing
      settled = path[%r{/games/#{BOOK}/(\d+)}, 1]
      break if %w[192 305].include?(settled)
    end

    assert_includes %w[192 305], settled, 'the match ends one way or the other'
    rolled = stats_of(entry.split('|')[1])
    assert_equal 1, rolled['endurance'], 'the table takes no lasting toll'
  end

  test 'sixth sense sweetens the samor throw' do
    pack '12', items: 'sword,sixth sense', stats: 'skill:15,endurance:25,endurance_max:25,gold:20,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '12', choice: 0 }

    path, query = landing
    rolled = query['rolled'].to_i
    assert_operator rolled, :>=, 2, 'the discipline adds two to the throw'
    expected = if rolled <= 3 then '58'
               elsif rolled <= 6 then '167'
               else '329'
               end
    assert_equal "/games/#{BOOK}/#{expected}", path
  end

  test 'gold stated as dice is thrown by the server and reported as it lands' do
    pack '25', items: 'sword,sixth sense', stats: 'skill:15,endurance:25,endurance_max:25,gold:0,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '25', choice: 0 }

    assert_equal "/games/#{BOOK}/116", landing.first
    rolled = stats_of(entry.split('|')[1])
    assert_includes 4..13, rolled['gold'], 'the throw plus five, less the crown for the room'
    assert_match(/gold\+\d+/, landing.last['fx'])
  end

  test 'the herbwarden of hammerdal restores by skill: everything, or half the losses' do
    pack '74', items: 'sword', stats: 'skill:15,endurance:10,endurance_max:26,gold:10,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '74', choice: 0 }
    assert_match(/endurance:18/, entry, 'half of sixteen lost comes back without Healing')

    pack '74', items: 'sword,healing', stats: 'skill:15,endurance:10,endurance_max:26,gold:10,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '74', choice: 0 }
    rolled = stats_of(entry.split('|')[1])
    assert_operator rolled['endurance'], :>=, 26, 'Healing restores the lot'
  end

  test 'every route in the second book leads somewhere real' do
    book = Gamebooks.find(BOOK)
    sections = book['sections']
    walk = lambda do |pick, where|
      pick['routes'].each do |route|
        landable = route['die'] || route['pick'] || sections.key?(route['to'])
        assert landable, "#{where}: a pick route leads nowhere"
        walk.call(route['pick'], where) if route['pick']
      end
    end
    sections.each do |id, section|
      (section['choices'] || []).each do |choice|
        assert sections.key?(choice['to']), "#{id} -> #{choice['to']}" if choice['to']
        walk.call(choice['pick'], id) if choice['pick']
      end
      %w[evade overtime].each do |rule|
        to = section.dig('combat', rule, 'to')
        assert sections.key?(to), "#{id}: #{rule}" unless to.nil?
      end
      %w[win lose].each do |outcome|
        to = section.dig('combat', 'contest', outcome)
        assert sections.key?(to), "#{id}: contest" unless to.nil?
      end
    end
    assert_equal(0, sections.count { |_, sec| sec['rnt'] })
  end
end
