# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# The Caverns of Kalte: carry-over from whichever earlier book was finished, the
# outfitting table, and the mechanics Kalte adds — Baknar oil against the cold, Kai
# ranks, wounds that end a fight by themselves, victories judged by their speed,
# rounds fought unscathed, and fangs that kill or miss entirely.
class LoneWolfThreeTest < ActionDispatch::IntegrationTest
  BOOK = 'the-caverns-of-kalte'
  # A Kai Lord standing on the last page of Book Two, six disciplines deep.
  VETERAN_TWO = '350|skill:19,endurance:27,endurance_max:29,gold:44,gold_max:50|' \
                'camouflage,hunting,sixth sense,tracking,mindshield,weaponskill in sword,' \
                'sommerswerd,sword,meal:2,crystal star pendant|'
  # One who only ever finished Book One.
  VETERAN_ONE = '350|skill:16,endurance:23,endurance_max:25,gold:12,gold_max:50|' \
                'camouflage,healing,sixth sense,tracking,mindblast,axe,meal:1|'

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

  def disciplines_in(held)
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    held.count { |item| draw.include?(item) || item.start_with?('weaponskill in ') }
  end

  test 'a kai lord who finished book two carries everything and learns a seventh skill' do
    cookies['CYOA'] = { 'fire-on-the-water' => VETERAN_TWO }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }

    assert_redirected_to "/games/#{BOOK}/armoury"
    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_equal [19, 29], [rolled['skill'], rolled['endurance_max']], 'the scores carry'
    assert_equal 50, rolled['gold'], 'forty-four plus a fresh pouch, capped at fifty'

    held = items.split(',')
    assert_includes held, 'sommerswerd', 'the sword of the sun crosses the sea'
    assert_includes held, 'crystal star pendant'
    assert_includes held, 'meal:2'
    assert_includes held, 'map of kalte'
    assert_includes held, 'armoury choice:2'
    assert_equal 7, disciplines_in(held), 'six carried, one learned on the road'
  end

  test 'finishing only book one still carries that kai lord into kalte' do
    cookies['CYOA'] = { 'fire-on-the-water' => '12|skill:15,endurance:20|sword|',
                        'flight-from-the-dark' => VETERAN_ONE }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }

    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_equal 16, rolled['skill'], 'book one is the fallback when book two is unfinished'
    assert_includes 22..31, rolled['gold'], 'twelve carried plus the Anskaven pouch'
    held = items.split(',')
    assert_includes held, 'axe'
    assert_equal 6, disciplines_in(held), 'five carried, one learned'
  end

  test 'with nothing finished, a fresh kai lord is rolled by the book three rules' do
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }

    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_includes 10..19, rolled['skill']
    assert_includes 20..29, rolled['endurance']
    assert_includes 10..19, rolled['gold']
    assert_equal 50, rolled['gold_max']
    held = items.split(',')
    assert_equal 5, disciplines_in(held)
    assert_includes held, 'map of kalte'
  end

  test 'the outfitting table honours exactly two picks and the waistcoat pays its two' do
    pack 'armoury', items: 'armoury choice:2'

    post '/games/take', params: { book: BOOK, item: 'padded leather waistcoat' }
    rolled = stats_of(entry.split('|')[1])
    assert_equal [27, 27], [rolled['endurance'], rolled['endurance_max']],
                 'the waistcoat lifts the score and the ceiling together'

    post '/games/take', params: { book: BOOK, item: 'warhammer' }
    held = entry.split('|')[2].split(',')
    assert_includes held, 'warhammer'
    assert_no_match(/armoury choice/, entry, 'both picks spent')

    get "/games/#{BOOK}/armoury"
    assert_no_match(/An Axe/, @response.body, 'no picks left, no more offers')
    post '/games/take', params: { book: BOOK, item: 'axe' }
    assert_not_includes entry.split('|')[2].split(','), 'axe', 'a third pick is refused'
  end

  # Kalte's cold is a mechanic: the Baknar oil the guides offer is what keeps it off.
  test 'baknar oil spares the endurance the cold would take' do
    pack '33', items: 'sword'
    post '/games/turn', params: { book: BOOK, from: '33', choice: 1 }
    assert_equal "/games/#{BOOK}/27", landing.first
    assert_match(/endurance:23/, entry, 'two points to the bitter wind')

    pack '33', items: 'sword,baknar oil'
    post '/games/turn', params: { book: BOOK, from: '33', choice: 1 }
    assert_match(/endurance:25/, entry, 'the oil keeps the cold out entirely')
  end

  # The Kai ranks are only a count of disciplines: five to set out, one per book won.
  test 'a kai rank gate opens to the veteran and stays shut to the novice' do
    pack '36', items: 'sword,sixth sense,camouflage,hunting,tracking,mindshield'
    get "/games/#{BOOK}/36"
    assert_match '124', @response.body, 'six disciplines: sensed, but not yet understood'
    assert_no_match(/341/, @response.body)

    pack '36', items: 'sword,sixth sense,camouflage,hunting,tracking,mindshield,healing,mindblast'
    get "/games/#{BOOK}/36"
    assert_match '341', @response.body, 'the seventh rank reads the Vagadyn Gate'
    assert_no_match(/turn to 124/, @response.body)

    pack '36', items: 'sword,camouflage,hunting,tracking,mindshield,healing'
    get "/games/#{BOOK}/36"
    assert_match '264', @response.body, 'without the sense, you walk in blind'
  end

  # A Kalkoth's barbed tongue: the least wound is a paralysing sting, and the fight
  # ends there rather than being fought out.
  test 'a wound the book acts on ends the fight where it stands' do
    pack '123', stats: 'skill:1,endurance:40,endurance_max:40,gold:5,gold_max:50'

    landed = nil
    20.times do
      post '/games/turn', params: { book: BOOK, from: '123', choice: 'fight' }
      path, query = landing
      landed = path
      break if query['you'].to_i.positive? || query.empty?
    end

    assert_equal "/games/#{BOOK}/66", landed, 'the sting carries you off mid-fight'
  end

  test 'a victory is judged by its speed where the book says so' do
    # The killing blow on the third round, with the creature down to its last point.
    pack '164', stats: 'skill:99,endurance:99,endurance_max:99,gold:5,gold_max:50',
                items: 'sommerswerd', fight: '0:1:2:0:99'
    post '/games/turn', params: { book: BOOK, from: '164', choice: 'fight' }
    assert_equal "/games/#{BOOK}/272", landing.first, 'felled inside five rounds'

    # The same kill, but on the sixth round: the old magician has paid for the delay.
    pack '164', stats: 'skill:99,endurance:99,endurance_max:99,gold:5,gold_max:50',
                items: 'sommerswerd', fight: '0:1:6:0:99'
    post '/games/turn', params: { book: BOOK, from: '164', choice: 'fight' }
    assert_equal "/games/#{BOOK}/324", landing.first, 'too slow, and Loi-Kymar suffers'
  end

  test 'a surprise attack leaves the first rounds unanswered' do
    pack '260', stats: 'skill:1,endurance:40,endurance_max:40,gold:5,gold_max:50'

    2.times do |round|
      post '/games/turn', params: { book: BOOK, from: '260', choice: 'fight' }
      assert_equal 0, landing.last['you'].to_i, "round #{round + 1} strikes twice unanswered"
    end
    assert_match(/endurance:40/, entry, 'not a point lost while the surprise holds')
  end

  # The Javek's fangs find the padded arm or the flesh: nothing, or everything.
  test 'the javek fangs are all or nothing' do
    pack '88', stats: 'skill:1,endurance:40,endurance_max:40,gold:5,gold_max:50'

    10.times do
      post '/games/turn', params: { book: BOOK, from: '88', choice: 'fight' }
      hurt = landing.last['you'].to_i
      assert(hurt.zero? || hurt >= 40, 'a Javek bite is a miss or a death, never a scratch')
      break if hurt.positive?
    end
  end

  test 'a discipline and the state of the reader sway a table throw' do
    # Section 86 picks the lock: skilled hands add three, so the throw cannot be low.
    pack '86', items: 'dagger,weaponskill in dagger'
    post '/games/turn', params: { book: BOOK, from: '86', choice: 0 }
    assert_operator landing.last['rolled'].to_i, :>=, 3, 'the skilled hand adds its three'

    # Section 155's ice staircase: strength steadies the descent, weakness betrays it.
    pack '155', stats: 'skill:15,endurance:24,endurance_max:25,gold:5,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '155', choice: 0 }
    assert_operator landing.last['rolled'].to_i, :>=, 1, 'over twenty endurance steadies you'

    pack '155', stats: 'skill:15,endurance:5,endurance_max:25,gold:5,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: '155', choice: 0 }
    assert_operator landing.last['rolled'].to_i, :<=, 7, 'weakness costs two from the throw'
  end

  test 'the sledge stores are taken as one press each, food by the handful' do
    pack '119', items: 'sword'
    get "/games/#{BOOK}/119"
    assert_match 'Pack food for five Meals', @response.body

    post '/games/take', params: { book: BOOK, item: 'meal' }
    post '/games/take', params: { book: BOOK, item: 'rope' }
    held = entry.split('|')[2].split(',')
    assert_includes held, 'meal:5'
    assert_includes held, 'rope'
  end

  test 'every route in the third book leads somewhere real' do
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
    %w[to else].each do |branch|
      to = combat.dig('win_within', branch)
      assert sections.key?(to), "#{id}: win_within" unless to.nil?
    end
  end
end
