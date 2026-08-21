# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# The Kingdoms of Terror: the first book of the Magnakai series, and the first that
# changes the rules rather than only the story. The Kai Disciplines of Books One to
# Five give way to three Magnakai ones the reader chooses; Weaponskill in a single
# weapon gives way to Weaponmastery in three; completing a Lore-circle pays a bonus;
# and a Bow is no use with an enemy already upon you.
class LoneWolfSixTest < ActionDispatch::IntegrationTest
  BOOK = 'the-kingdoms-of-terror'
  # A Kai Lord out of Vassagonia: five Kai Disciplines, a sword he is skilled with, the
  # sword of the sun, and wounds he never had a chance to sleep off.
  VETERAN = '350|skill:21,endurance:27,endurance_max:31,gold:46,gold_max:50|' \
            'camouflage,hunting,sixth sense,tracking,healing,weaponskill in sword,' \
            'sword,sommerswerd,crystal star pendant,meal:2|'

  # The title page sends a returning Kai Master to his Disciplines first and a fresh
  # one straight to the armoury, in the order the book's own front matter runs.
  ARMOURY_CHOICE = 2
  LESSON = 0
  # A fight with nothing else going on: one thief, no shielded rounds, no evade, no
  # bonus that turns on a Discipline — so the arithmetic under test is the only thing
  # moving.
  PLAIN_FIGHT = '42'

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

  def held_by(cookie = entry)
    cookie.split('|')[2].split(',')
  end

  test 'the kai lord rides into the magnakai series with his scores, his kit, and no kai skills' do
    cookies['CYOA'] = { 'shadow-on-the-sand' => VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: LESSON }

    assert_redirected_to "/games/#{BOOK}/newskill"
    rolled = stats_of(entry.split('|')[1])
    assert_equal 21, rolled['skill'], 'the combat skill carries'
    assert_equal [27, 27], [rolled['endurance'], rolled['endurance_max']],
                 'the current score carries, wounds and all, and becomes the ceiling'
    assert_equal 50, rolled['gold'], 'forty-six plus a fresh pouch, capped at the belt pouch fifty'

    held = held_by
    assert_includes held, 'sommerswerd', 'Special Items carry into the new series'
    assert_includes held, 'crystal star pendant'
    assert_includes held, 'sword', 'and so do Weapons'
    assert_includes held, 'meal:2'
    # "Books 1-5: you can carry your COMBAT SKILL and ENDURANCE, Weapons and Special
    # Items" — the Kai Disciplines are not on that list; the Magnakai replace them.
    ['camouflage', 'hunting', 'sixth sense', 'tracking', 'healing'].each do |kai|
      assert_not_includes held, kai, 'the Kai Disciplines do not cross into the Magnakai'
    end
    assert_not_includes held, 'weaponskill in sword'
    assert_includes held, 'magnakai choice:3', 'three Magnakai Disciplines to choose'
    assert_includes held, 'armoury choice:5'
  end

  test 'the reader chooses three magnakai disciplines and no more' do
    cookies['CYOA'] = { 'shadow-on-the-sand' => VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: LESSON }
    assert_redirected_to "/games/#{BOOK}/newskill"

    %w[curing divination nexus].each do |skill|
      post '/games/take', params: { book: BOOK, item: skill }
      assert_includes held_by, skill
    end
    assert_no_match(/magnakai choice/, entry, 'all three spent')

    post '/games/take', params: { book: BOOK, item: 'invisibility' }
    assert_not_includes held_by, 'invisibility', 'a fourth is refused'
  end

  test 'weaponmastery brings three weapons of the readers choosing' do
    cookies['CYOA'] = { 'shadow-on-the-sand' => VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: LESSON }

    post '/games/take', params: { book: BOOK, item: 'weaponmastery' }
    assert_includes held_by, 'weapon choice:3', 'skilled in three of the weapons'

    post '/games/turn', params: { book: BOOK, from: 'newskill', choice: 0 }
    assert_redirected_to "/games/#{BOOK}/weaponmaster"
    %w[sword axe bow].each do |arm|
      post '/games/take', params: { book: BOOK, item: "weaponmastery in #{arm}" }
    end
    held = held_by
    assert_includes held, 'weaponmastery in bow'
    assert_no_match(/weapon choice/, entry, 'three ticks, three weapons')

    post '/games/take', params: { book: BOOK, item: 'weaponmastery in mace' }
    assert_not_includes held_by, 'weaponmastery in mace', 'a fourth weapon is refused'
  end

  # "By mastering all of the Magnakai Disciplines of a Lore-circle you may add the
  # extra bonus points shown" — the Circle of Fire is Weaponmastery and Huntmastery,
  # worth +1 COMBAT SKILL and +2 ENDURANCE, and it is paid once.
  test 'closing a lore circle pays its bonus, once' do
    pack 'newskill', items: 'magnakai choice:3',
                     stats: 'skill:20,endurance:28,endurance_max:28,gold:20,gold_max:50'

    post '/games/take', params: { book: BOOK, item: 'huntmastery' }
    assert_equal [20, 28], stats_of(entry.split('|')[1]).values_at('skill', 'endurance'),
                 'half a circle pays nothing'

    post '/games/take', params: { book: BOOK, item: 'weaponmastery' }
    rolled = stats_of(entry.split('|')[1])
    assert_equal [21, 30, 30], rolled.values_at('skill', 'endurance', 'endurance_max'),
                 'the Circle of Fire: +1 combat skill, +2 endurance, ceiling and all'

    post '/games/take', params: { book: BOOK, item: 'curing' }
    assert_equal 21, stats_of(entry.split('|')[1])['skill'], 'the circle is not paid twice'
  end

  test 'weaponmastery adds its three to the weapon it is mastery of, and nothing to the rest' do
    id = PLAIN_FIGHT
    foe = Gamebooks.find(BOOK)['sections'][id]['combat']['enemies'].first

    pack id, items: 'sword,weaponmastery,weaponmastery in sword'
    post '/games/turn', params: { book: BOOK, from: id, choice: 'fight' }
    _, query = landing
    want = LoneWolf.strike(20 + 3 - foe['skill'], query['rn'].to_i)
    assert_equal want, [query['foe'].to_i, query['you'].to_i], 'mastered: skill plus three'

    pack id, items: 'axe,weaponmastery,weaponmastery in sword'
    post '/games/turn', params: { book: BOOK, from: id, choice: 'fight' }
    _, query = landing
    want = LoneWolf.strike(20 - foe['skill'], query['rn'].to_i)
    assert_equal want, [query['foe'].to_i, query['you'].to_i], 'an axe he never mastered adds nothing'
  end

  # "A Bow cannot be used in hand-to-hand combat... if you enter combat armed only
  # with a Bow, deduct 4 points and fight with your bare hands."
  test 'a bow is no weapon with the enemy already upon you' do
    id = PLAIN_FIGHT
    foe = Gamebooks.find(BOOK)['sections'][id]['combat']['enemies'].first

    pack id, items: 'bow,quiver,arrow:6'
    post '/games/turn', params: { book: BOOK, from: id, choice: 'fight' }
    _, query = landing
    want = LoneWolf.strike(20 - 4 - foe['skill'], query['rn'].to_i)
    assert_equal want, [query['foe'].to_i, query['you'].to_i], 'bare-handed, and four the poorer'

    get "/games/#{BOOK}/#{id}"
    assert_match 'bare-handed', @response.body
  end

  test 'the armoury honours exactly five picks and the waistcoat pays its endurance' do
    pack 'armoury', items: 'armoury choice:5'

    post '/games/take', params: { book: BOOK, item: 'padded leather waistcoat' }
    rolled = stats_of(entry.split('|')[1])
    assert_equal [30, 30], rolled.values_at('endurance', 'endurance_max'),
                 'the waistcoat lifts the score and the ceiling'

    post '/games/take', params: { book: BOOK, item: 'quiver' }
    assert_includes held_by, 'arrow:6', 'the Quiver contains six Arrows'

    %w[sword rope tinderbox].each { |item| post '/games/take', params: { book: BOOK, item: item } }
    assert_no_match(/armoury choice/, entry, 'five picks, all spent')

    post '/games/take', params: { book: BOOK, item: 'axe' }
    assert_not_includes held_by, 'axe', 'a sixth is refused'
  end

  test 'with nothing finished, a kai master is rolled by the book six rules' do
    post '/games/turn', params: { book: BOOK, from: 'start', choice: ARMOURY_CHOICE }

    rolled = stats_of(entry.split('|')[1])
    assert_includes 10..19, rolled['skill']
    assert_includes 20..29, rolled['endurance']
    assert_includes 10..19, rolled['gold']
    assert_equal 50, rolled['gold_max']

    held = held_by
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    assert_equal 3, held.count { |item| draw.include?(item) }, 'three Magnakai Disciplines'
    assert_includes held, 'map of the stornlands'
    next unless held.include?('weaponmastery')

    assert_equal 3, held.count { |item| item.start_with?('weaponmastery in ') },
                 'a rolled Kai Master has his three weapons drawn for him'
  end

  test 'every page of the book can be reached and read' do
    book = Gamebooks.find(BOOK)
    book['sections'].each_key do |id|
      pack id, items: 'sword,curing,divination,huntmastery'
      get "/games/#{BOOK}/#{id}"
      assert_response :success, "section #{id} does not render"
    end
  end
end
