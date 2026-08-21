# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# Shadow on the Sand: carry-over from any earlier book, a quayside store that allows
# four picks, and what Vassagonia adds — a wound that festers with every page turned
# until a Laumspur potion answers it, an arm the sewer leaves numb, an unlucky throw
# on a swaying plank, and two throws set against each other on a dark stair.
class LoneWolfFiveTest < ActionDispatch::IntegrationTest
  BOOK = 'shadow-on-the-sand'
  CHASM_VETERAN = '400|skill:21,endurance:29,endurance_max:31,gold:45,gold_max:50|' \
                  'camouflage,hunting,sixth sense,tracking,mindshield,healing,mindblast,' \
                  'weaponskill in sword,sommerswerd,sword,meal:2,badge of rank|'

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

  test 'the fifth book stands on the series page' do
    get '/games/series/lone-wolf'
    assert_match 'Book Five - Shadow on the Sand', @response.body
  end

  test 'a kai lord out of Ruanon sails on with everything and a ninth discipline' do
    cookies['CYOA'] = { 'the-chasm-of-doom' => CHASM_VETERAN }.to_json
    post '/games/turn', params: { book: BOOK, from: 'start', choice: 0 }

    assert_redirected_to "/games/#{BOOK}/armoury"
    _section, stats, items = entry.split('|')
    rolled = stats_of(stats)
    assert_equal 21, rolled['skill']
    assert_equal 31, rolled['endurance'], 'rested to the ceiling between adventures'
    assert_equal 50, rolled['gold'], 'the pouch cannot hold more than fifty'

    held = items.split(',')
    assert_includes held, 'sommerswerd'
    assert_includes held, 'map of vassagonia'
    assert_includes held, 'armoury choice:4'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    skills = held.count { |i| draw.include?(i) || i.start_with?('weaponskill in ') }
    assert_equal 9, skills, 'eight carried, one more learned'
  end

  test 'the quayside stores allow four picks and no more' do
    pack 'armoury', items: 'armoury choice:4'
    %w[dagger sword spear mace].each { |item| post '/games/take', params: { book: BOOK, item: item } }

    assert_no_match(/armoury choice/, entry, 'all four spent')
    get "/games/#{BOOK}/armoury"
    assert_no_match(/A Shield/, @response.body, 'nothing left to spend')
  end

  # Section 63: "Deduct 2 ENDURANCE points for every section through which you pass,
  # until you discover and swallow a Potion of Laumspur."
  test 'an untended wound festers with every page until a potion answers it' do
    kit = 'skill:18,endurance:30,endurance_max:30,gold:5,gold_max:50'
    pack '63', stats: kit, items: 'sword,infected wound,potion:1'

    post '/games/turn', params: { book: BOOK, from: '63', choice: 1 }
    assert_match(/endurance:28/, entry, 'two points to the wound on the way out')

    # The potion is a standing green offer, and swallowing it lifts the wound.
    get "/games/#{BOOK}/#{entry.split('|').first}"
    assert_match(/Drink a Potion of Laumspur/, @response.body)
    post '/games/use', params: { book: BOOK, item: 'potion' }
    assert_equal 'infected wound', landing.last['cured']
    assert_not_includes entry.split('|')[2].split(','), 'infected wound'
    assert_match(/endurance:30/, entry, 'and it mends its four, capped at the ceiling')
  end

  # Section 166: a numbed arm costs Combat Skill and makes a shield useless.
  test 'a numb arm costs combat skill and denies the shield' do
    kit = 'skill:18,endurance:30,endurance_max:30,gold:5,gold_max:50'
    pack '375', stats: kit, items: 'sword,shield'
    get "/games/#{BOOK}/375"
    assert_match 'Attack ratio +3.', @response.body, 'eighteen against seventeen, and the shield'

    pack '375', stats: kit, items: 'sword,shield,numb arm'
    get "/games/#{BOOK}/375"
    assert_match 'Attack ratio -2.', @response.body,
                 'three off for the arm, and the shield no longer counts'
  end

  # Section 357: fighting on a swaying plank, a single unlucky number ends it.
  test 'an unlucky throw on the plank pitches the reader off it' do
    pack '357', stats: 'skill:20,endurance:60,endurance_max:60,gold:5,gold_max:50', items: 'sword'

    landed = nil
    120.times do
      pack '357', stats: 'skill:20,endurance:60,endurance_max:60,gold:5,gold_max:50', items: 'sword'
      post '/games/turn', params: { book: BOOK, from: '357', choice: 'fight' }
      path, query = landing
      next unless query['rn'].to_i == 1 || query.empty?

      landed = path
      break
    end
    assert_equal "/games/#{BOOK}/293", landed, 'a one and you are over the edge'
  end

  # Section 360: two throws, quickness against quickness.
  test 'two throws set against each other settle the dark stair' do
    pack '360', items: 'sword'
    post '/games/turn', params: { book: BOOK, from: '360', choice: 0 }

    path, = landing
    assert_includes %w[226 297 334].map { |id| "/games/#{BOOK}/#{id}" }, path
  end

  # Sections 10 and 176: the Sharnazim "take your Backpack, your Weapons, your Gold
  # Crowns and all your Special Items" — and section 14 hands every bit of it back.
  test 'a gaoler impounds everything and freedom returns it' do
    kit = 'skill:19,endurance:30,endurance_max:30,gold:20,gold_max:50'
    pack '10', stats: kit, items: 'sword,shield,meal:2,gold key'
    post '/games/turn', params: { book: BOOK, from: '10', choice: 0 }

    stats, items = entry.split('|')[1, 2]
    assert_equal 0, stats_of(stats)['gold'], 'the purse is taken'
    assert items.split(',').all? { |i| i.start_with?('impounded ') }, 'and so is everything else'
    assert_no_match(/(\A|,)sword/, items, 'an impounded sword arms nobody')

    from = Gamebooks.find(BOOK)['sections'].find { |_, sec| (sec['choices'] || []).any? { |c| c['to'] == '14' } }
    index = from.last['choices'].index { |c| c['to'] == '14' }
    pack from.first, stats: stats, items: items
    post '/games/turn', params: { book: BOOK, from: from.first, choice: index }

    stats, items = entry.split('|')[1, 2]
    assert_equal 20, stats_of(stats)['gold'], 'the purse comes back whole'
    assert_equal ['sword', 'shield', 'meal:2', 'gold key'].sort, items.split(',').sort
  end

  # Section 353: underground "there is no sun from which the sword can draw its
  # power" — so the sword of the sun fights as the plain sword it also is.
  test 'a sword robbed of its power is still a sword' do
    kit = 'skill:19,endurance:30,endurance_max:30,gold:5,gold_max:50'
    held = 'sommerswerd,weaponskill in sword,mindshield'

    pack '355', stats: kit, items: held
    get "/games/#{BOOK}/355"
    assert_match 'Fighting with the sommerswerd (skill +10).', @response.body,
                 'in the open it is everything the book says'

    pack '353', stats: kit, items: held
    get "/games/#{BOOK}/353"
    assert_match 'Fighting with the sommerswerd (skill +2).', @response.body,
                 'underground it is worth no more than a skilled sword'
  end

  # Every throw's ranges were read out of the book's own labels; spot-check one.
  test 'a throw derived from its label keeps the book ranges' do
    chimney_throw = Gamebooks.find(BOOK)['sections']['23']['choices'].first['pick']
    spans = chimney_throw['routes'].map { |r| [r['min'], r['max'], r['to']] }
    assert_equal [[-3, -1, '77'], [0, 6, '192'], [7, 11, '114']], spans
    # Hunting steadies the climb; a numbed arm makes it far worse, as the book says.
    assert_equal([{ 'item' => 'hunting', 'add' => 2 },
                  { 'item' => 'numb arm', 'add' => -3 }], chimney_throw['plus'])
  end
end
