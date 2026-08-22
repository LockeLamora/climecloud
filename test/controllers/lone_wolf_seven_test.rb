# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# Castle Death: the second Magnakai volume. The carry-over arithmetic is what is new
# here — one further Magnakai Discipline for every Magnakai book finished, but the
# three a Kai Master Superior begins with for a reader arriving straight out of the
# Kai series — and with the fourth Discipline comes the rank of Primate, which the
# book's Improved Disciplines gate on.
class LoneWolfSevenTest < ActionDispatch::IntegrationTest
  BOOK = 'castle-death'
  # A Kai Master out of the Stornlands: three Magnakai Disciplines, the sword of the
  # sun, and wounds from the last book that no rest has mended.
  MAGNAKAI_VETERAN = '350|skill:22,endurance:26,endurance_max:30,gold:44,gold_max:50|' \
                     'curing,divination,huntmastery,sword,sommerswerd,' \
                     'crystal star pendant,meal:2|'
  # A Kai Lord who never took up the Magnakai at all.
  KAI_VETERAN = '350|skill:20,endurance:24,endurance_max:28,gold:20,gold_max:50|' \
                'camouflage,hunting,sixth sense,tracking,healing,weaponskill in sword,' \
                'sword,sommerswerd|'

  LESSON = 0
  ARMOURY_CHOICE = 2
  PLAIN_FIGHT = '8'

  def pack(section, stats: 'skill:20,endurance:28,endurance_max:28,gold:20,gold_max:50',
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

  def held_by
    entry.split('|')[2].split(',')
  end

  test 'a kai master out of the kingdoms of terror gains one further discipline' do
    cookies['CYOA'] = { 'the-kingdoms-of-terror' => MAGNAKAI_VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: LESSON }

    assert_redirected_to "/games/#{BOOK}/newskill"
    rolled = stats_of(entry.split('|')[1])
    assert_equal 22, rolled['skill']
    assert_equal [26, 26], [rolled['endurance'], rolled['endurance_max']],
                 'the current score carries and becomes the new ceiling'
    assert_equal 50, rolled['gold'], 'forty-four plus a fresh pouch, capped at fifty'

    held = held_by
    %w[curing divination huntmastery].each { |skill| assert_includes held, skill }
    assert_includes held, 'sommerswerd'
    assert_includes held, 'magnakai choice:1',
                    'one bonus Discipline for the one Magnakai adventure completed'
  end

  # "You may choose one bonus Magnakai Discipline for every Lone Wolf Magnakai
  # adventure you successfully complete (Books 6-12)" — none of them, for a reader
  # who has only the Kai books behind them, so they begin as a Kai Master Superior.
  test 'a kai lord arriving straight from the first series picks the opening three' do
    cookies['CYOA'] = { 'shadow-on-the-sand' => KAI_VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: LESSON }

    held = held_by
    assert_includes held, 'magnakai choice:3', 'the three a Kai Master Superior begins with'
    ['camouflage', 'hunting', 'sixth sense', 'tracking', 'healing'].each do |kai|
      assert_not_includes held, kai, 'the Kai Disciplines give way to the Magnakai'
    end
    assert_not_includes held, 'weaponskill in sword'
    assert_includes held, 'sommerswerd', 'but the Special Items and Weapons cross over'
    assert_includes held, 'sword'
  end

  test 'the reader chooses their magnakai disciplines and no more' do
    pack 'newskill', items: 'curing,divination,huntmastery,magnakai choice:1'

    post '/games/take', params: { book: BOOK, item: 'nexus' }
    assert_includes held_by, 'nexus'
    assert_no_match(/magnakai choice/, entry, 'the one pick is spent')

    post '/games/take', params: { book: BOOK, item: 'invisibility' }
    assert_not_includes held_by, 'invisibility', 'a second is refused'
  end

  # Rank is the count of Disciplines mastered, and the Magnakai count their own: a Kai
  # Master with four is a Primate, and Book Seven's Improved Disciplines start there.
  # Counting the Kai names instead gave every Magnakai reader a rank of nothing.
  test 'the rank of primate opens the improved disciplines' do
    superior = 'animal control,curing,huntmastery'
    primate = "#{superior},divination"
    gate = Gamebooks.find(BOOK)['sections']['34']['choices'][1]
    assert_equal 4, gate['rank'], 'section 34 asks for the rank of Primate'

    pack '34', items: superior
    get "/games/#{BOOK}/34"
    assert_response :success
    assert_no_match(/#{Regexp.escape(gate['label'][0, 40])}/, @response.body,
                    'three Disciplines is Kai Master Superior, and the branch is not theirs')

    pack '34', items: primate
    get "/games/#{BOOK}/34"
    assert_match(/#{Regexp.escape(gate['label'][0, 40])}/, @response.body,
                 'the fourth Discipline makes a Primate, and the branch opens')
  end

  test 'the elder magi allow exactly five picks and the quiver brings its arrows' do
    pack 'armoury', items: 'armoury choice:5'

    post '/games/take', params: { book: BOOK, item: 'quiver' }
    assert_includes held_by, 'arrow:6', 'the Quiver contains six Arrows'

    %w[sword rope lantern].each { |item| post '/games/take', params: { book: BOOK, item: item } }
    post '/games/take', params: { book: BOOK, item: 'meal' }
    assert_no_match(/armoury choice/, entry, 'five picks, all spent')

    post '/games/take', params: { book: BOOK, item: 'dagger' }
    assert_not_includes held_by, 'dagger', 'a sixth is refused'
  end

  test 'a bow is no weapon hand to hand, and a mastered weapon is worth three' do
    foe = Gamebooks.find(BOOK)['sections'][PLAIN_FIGHT]['combat']['enemies'].first

    pack PLAIN_FIGHT, items: 'bow,quiver,arrow:6'
    post '/games/turn', params: { book: BOOK, from: PLAIN_FIGHT, choice: 'fight' }
    _, query = landing
    assert_equal LoneWolf.strike(20 - 4 - foe['skill'], query['rn'].to_i),
                 [query['foe'].to_i, query['you'].to_i], 'bare-handed, and four the poorer'

    pack PLAIN_FIGHT, items: 'mace,weaponmastery,weaponmastery in mace'
    post '/games/turn', params: { book: BOOK, from: PLAIN_FIGHT, choice: 'fight' }
    _, query = landing
    assert_equal LoneWolf.strike(20 + 3 - foe['skill'], query['rn'].to_i),
                 [query['foe'].to_i, query['you'].to_i], 'mastered: skill plus three'
  end

  # "You cannot make use of a shield or any two-handed weapon during the combat, and
  # you must treble any ENDURANCE point losses you sustain."
  test 'the lekhor bars your shield and trebles every wound' do
    foe = Gamebooks.find(BOOK)['sections']['76']['combat']['enemies'].first

    pack '76', items: 'sword,shield,weaponmastery,weaponmastery in sword'
    post '/games/turn', params: { book: BOOK, from: '76', choice: 'fight' }
    _, query = landing
    table_foe, table_you = LoneWolf.strike(20 + 3 - foe['skill'], query['rn'].to_i)
    assert_equal table_foe, query['foe'].to_i, 'the shield adds nothing here'
    expected = table_you == LoneWolf::KILLED ? 28 : table_you * 3
    assert_equal expected, query['you'].to_i, 'and every wound counts three times'
  end

  # "Unless you have the Magnakai Discipline of Curing, double all ENDURANCE points you
  # lose during this combat due to the venomous bite."
  test 'curing answers the venom that would double every wound' do
    foe = Gamebooks.find(BOOK)['sections']['301']['combat']['enemies'].first

    pack '301', items: 'sword'
    post '/games/turn', params: { book: BOOK, from: '301', choice: 'fight' }
    _, query = landing
    _, table_you = LoneWolf.strike(20 - foe['skill'], query['rn'].to_i)
    assert_equal(table_you == LoneWolf::KILLED ? 28 : table_you * 2, query['you'].to_i)

    pack '301', items: 'sword,curing'
    post '/games/turn', params: { book: BOOK, from: '301', choice: 'fight' }
    _, query = landing
    _, table_you = LoneWolf.strike(20 - foe['skill'], query['rn'].to_i)
    assert_equal(table_you == LoneWolf::KILLED ? 28 : table_you, query['you'].to_i,
                 'the healer takes the bite at its face value')
  end

  test 'with nothing finished, a kai master is rolled by the book seven rules' do
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    rolled = stats_of(entry.split('|')[1])
    assert_includes 10..19, rolled['skill']
    assert_includes 20..29, rolled['endurance']
    assert_includes 10..19, rolled['gold']

    held = held_by
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    assert_equal 3, held.count { |item| draw.include?(item) }, 'three Magnakai Disciplines'
    assert_includes held, 'map of dessi'
  end

  test 'every page of the book can be reached and read' do
    Gamebooks.find(BOOK)['sections'].each_key do |id|
      pack id, items: 'sword,curing,divination,huntmastery'
      get "/games/#{BOOK}/#{id}"
      assert_response :success, "section #{id} does not render"
    end
  end
end
