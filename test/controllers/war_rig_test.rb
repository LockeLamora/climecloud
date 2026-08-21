# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# The combat and bookkeeping layers, proven on the war-rig fixture. The random number
# in a combat round is the server's, but it is echoed back in the redirect — so each
# test recomputes the Combat Results Table row for the ratio it expects and checks the
# damage matches. A wrong ratio picks a different column and the numbers give it away.
class WarRigTest < ActionDispatch::IntegrationTest
  BOOK = 'war-rig'

  def pack(section, stats: 'skill:10,stamina:20,stamina_max:20,gold:5,gold_max:50',
           items: 'club', fight: '')
    cookies['CYOA'] = { BOOK => "#{section}|#{stats}|#{items}|#{fight}" }.to_json
  end

  def entry
    JSON.parse(cookies['CYOA'])[BOOK]
  end

  def landing
    query = Rack::Utils.parse_query(URI(@response.headers['Location']).query.to_s)
    [URI(@response.headers['Location']).path, query]
  end

  def fight_round(from)
    post '/games/turn', params: { book: BOOK, from: from, choice: 'fight' }
  end

  def assert_ratio(expected, note)
    _, query = landing
    want_foe, want_you = LoneWolf.strike(expected, query['rn'].to_i)
    assert_equal [want_foe, want_you], [query['foe'].to_i, query['you'].to_i],
                 "#{note}: rn #{query['rn']} should land as ratio #{expected}"
  end

  test 'a fresh character is endowed by the equipment table and typed weaponskill' do
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }

    _section, stats, items = entry.split('|')
    rolled = stats.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }
    assert_equal [22, 22, 50], [rolled['stamina'], rolled['stamina_max'], rolled['gold_max']],
                 'the club draw adds two stamina and lifts the ceiling with it'
    held = items.split(',')
    assert_includes held, 'club'
    assert_includes held, 'weaponskill in sabre', 'the one-entry table types the skill'
    assert_includes held, 'tonic:1'
  end

  test 'bare hands, a plain weapon and the skilled weapon each set their own ratio' do
    pack 'shade', items: 'salve'
    fight_round 'shade'
    assert_ratio(-4, 'unarmed pays the four')

    pack 'shade', items: 'club'
    fight_round 'shade'
    assert_ratio(0, 'an unskilled club is level')

    pack 'shade', items: 'sabre,weaponskill in sabre'
    fight_round 'shade'
    assert_ratio(2, 'the skilled sabre earns its two')
  end

  test 'mindblast adds two, except against the immune' do
    pack 'shade', items: 'club,mindblast'
    fight_round 'shade'
    assert_ratio(2, 'the shade has no defence against the mind')

    # The pit: modifier +1, surprise +2, no torch -3 — a net of zero — and the ogre
    # shrugs the mindblast, so the two never lands.
    pack 'pit', items: 'club,mindblast'
    fight_round 'pit'
    assert_ratio(0, 'the ogre is immune, so the sum stays at nothing')
  end

  test 'surprise lasts one round and a torch lifts the dark' do
    pack 'pit', items: 'club,torch'
    fight_round 'pit'
    assert_ratio(3, 'first round: +1 modifier, +2 surprise, torch lit')

    fight = entry.split('|', 4).last
    pack 'pit', items: 'club,torch', fight: fight
    fight_round 'pit'
    assert_ratio(1, 'second round: the surprise is spent')
  end

  test 'a fight the book cuts short drags the reader off at the stated round' do
    pack 'pit', stats: 'skill:10,stamina:99,stamina_max:99,gold:5,gold_max:50'
    3.times { fight_round 'pit' }

    path, query = landing
    assert_equal "/games/#{BOOK}/field", path, 'round three ends in the field, win or no win'
    assert_equal 'nothing', query['ate'], 'and the field demands a meal there is not'
    assert_match(/^field\|/, entry)
  end

  test 'evading is refused before the stated round and honoured after it' do
    pack 'pit', stats: 'skill:10,stamina:99,stamina_max:99,gold:5,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: 'pit', choice: 'evade' }
    assert_match(/^pit\|/, entry, 'no flight before a round is stood')
    assert_equal "/games/#{BOOK}/pit", landing.first

    fight_round 'pit'
    post '/games/turn', params: { book: BOOK, from: 'pit', choice: 'evade' }
    assert_equal "/games/#{BOOK}/camp", landing.first
    assert_match(/^camp\|/, entry)
  end

  test 'an offer taken mid-fight joins the belt without breaking the fight' do
    pack 'pit', items: 'club,weaponskill in sabre'
    fight_round 'pit'
    fight = entry.split('|', 4).last

    post '/games/take', params: { book: BOOK, item: 'sabre' }
    assert_includes entry.split('|')[2].split(','), 'sabre'
    assert_equal fight, entry.split('|', 4).last, 'the round count and wounds stand'

    fight_round 'pit'
    assert_ratio(0, 'second round: +1 modifier, -3 dark, +2 for the sabre in skilled hands')
  end

  test 'the random number table is picked by the server and a route can carry a wound' do
    pack 'camp'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 1 }

    path, query = landing
    assert_equal "/games/#{BOOK}/field", path
    assert_equal 1, query['rolled'].to_i, 'a 1d1 pick can only throw a one'
    assert_match(/stamina:15/, entry, 'two stamina to the ford, three more to an empty pack at supper')
  end

  test 'a pick can chain into deeper picks and the last route can be the end' do
    pack 'camp'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 2 }

    assert_equal "/games/#{BOOK}/camp", landing.first, 'the bog ends the story where it stands'
    assert_match(/stamina:0/, entry)

    get "/games/#{BOOK}/camp"
    assert_match I18n.t('games.the_end'), @response.body
  end

  test 'a stat fork shows only the line that is true and refuses the other' do
    pack 'camp'
    get "/games/#{BOOK}/camp"
    assert_match 'Take the poor road', @response.body
    assert_no_match(/Take the rich road/, @response.body, 'five gold is not rich')

    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 3 }
    assert_equal "/games/#{BOOK}/camp", landing.first, 'the rich road refuses five gold'
    assert_match(/^camp\|/, entry)

    pack 'camp', stats: 'skill:10,stamina:20,stamina_max:20,gold:20,gold_max:50'
    get "/games/#{BOOK}/camp"
    assert_match 'Take the rich road', @response.body
    assert_no_match(/Take the poor road/, @response.body)
  end

  test 'a without gate hides its line while the named thing is held' do
    pack 'camp', items: 'club,charm'
    get "/games/#{BOOK}/camp"
    assert_no_match(/Bury the charm/, @response.body)

    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 5 }
    assert_equal "/games/#{BOOK}/camp", landing.first, 'holding the charm bars the burial'

    pack 'camp', items: 'club'
    get "/games/#{BOOK}/camp"
    assert_match 'Bury the charm', @response.body
  end

  test 'a demanded meal is eaten, hunted for, served as laumspur, or paid in strength' do
    pack 'camp', items: 'club,meal:2'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }
    assert_equal 'meal', landing.last['ate']
    assert_match(/club,meal:1\|/, entry, 'one meal eaten, one left')

    pack 'camp', items: 'club,hunting,meal:1'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }
    assert_equal 'hunting', landing.last['ate']
    assert_match(/meal:1\|/, entry, 'the hunter keeps the meal')

    pack 'camp', items: 'club,laumspur:1', stats: 'skill:10,stamina:10,stamina_max:20,gold:5,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }
    assert_equal 'laumspur', landing.last['ate']
    assert_match(/stamina:13/, entry, 'laumspur feeds and heals its three')

    pack 'camp', items: 'club'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }
    assert_equal 'nothing', landing.last['ate']
    assert_match(/stamina:17/, entry, 'going hungry costs three')

    get "/games/#{BOOK}/field", params: { ate: 'nothing' }
    assert_match(/<span class='error'>Nothing to eat/, @response.body)
  end

  test 'the gauntlet lifts one thing from the pack and the stone lands as rolled' do
    pack 'camp', items: 'club,meal:2'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 8 }

    assert_equal 'meal', landing.last['lost'], 'the only backpack thing is a meal'
    assert_match(/club,meal:1\|/, entry, 'one meal lifted, the club kept on the belt')
    assert_match(/stamina:16/, entry, 'a 1d1 stone always hits for four')

    pack 'camp', items: 'club'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 8 }
    assert_equal 'club', landing.last['lost'], 'an empty pack costs a weapon instead'
  end

  test 'offers withdraw once held or barred, and a full belt gives up its plainest arm' do
    pack 'armoury', items: 'club,weaponskill in sabre'
    get "/games/#{BOOK}/armoury"
    assert_match 'Take the sabre', @response.body
    assert_match 'Take the torch', @response.body

    post '/games/take', params: { book: BOOK, item: 'sabre' }
    assert_equal 'sabre', landing.last['took']
    get "/games/#{BOOK}/armoury"
    assert_no_match(/Take the sabre/, @response.body, 'held, so withdrawn')
    assert_no_match(/Take the torch/, @response.body, 'barred by the sabre')

    post '/games/take', params: { book: BOOK, item: 'pike' }
    assert_equal 'club', landing.last['gave'], 'two arms carried: the unskilled club goes'
    held = entry.split('|')[2].split(',')
    assert_includes held, 'pike'
    assert_not_includes held, 'club'
  end

  test 'a bundled offer hands over its companions in the same press' do
    pack 'armoury', items: 'club'
    post '/games/take', params: { book: BOOK, item: 'flint' }

    held = entry.split('|')[2].split(',')
    assert_includes held, 'flint'
    assert_includes held, 'steel', 'the companion arrives with the main find'
  end

  test 'the combat panel names the weapon the engine fights with' do
    pack 'pit', items: 'club'
    get "/games/#{BOOK}/pit"
    assert_match 'Fighting with the club.', @response.body

    pack 'pit', items: 'sabre,weaponskill in sabre'
    get "/games/#{BOOK}/pit"
    assert_match(/Fighting with the sabre \(skill \+2\)/, @response.body)

    pack 'pit', items: 'salve'
    get "/games/#{BOOK}/pit"
    assert_match(/Fighting bare-handed \(skill -4\)/, @response.body)
  end

  test 'an exchange offer takes a weapon in payment and stands only while one is held' do
    pack 'smithy', items: 'club'
    post '/games/take', params: { book: BOOK, item: 'sabre' }
    assert_equal({ 'took' => 'sabre', 'gave' => 'club' }, landing.last.slice('took', 'gave'))

    pack 'smithy', items: 'salve'
    get "/games/#{BOOK}/smithy"
    assert_no_match(/Exchange a weapon/, @response.body, 'no arm to give, no exchange')
    post '/games/take', params: { book: BOOK, item: 'sabre' }
    assert_no_match(/sabre/, entry.split('|')[2], 'the refusal writes nothing')
  end

  test 'a battle draught works mid-fight only and its virtue dies with the fight' do
    pack 'shade', items: 'club,tonic:1'
    post '/games/use', params: { book: BOOK, item: 'tonic' }
    assert_equal '0:99:0:4', entry.split('|', 4).last, 'the bonus rides the fight string'
    assert_no_match(/tonic/, entry.split('|')[2], 'the draught is spent')

    fight_round 'shade'
    assert_ratio(4, 'the tonic adds its four to a level duel')

    pack 'camp', items: 'club,tonic:1'
    post '/games/use', params: { book: BOOK, item: 'tonic' }
    assert_match(/tonic:1/, entry, 'no fight, no drinking: the tonic keeps')
  end

  test 'gold stops at the pouch and a healer mends a point each quiet page' do
    pack 'camp'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 11 }
    assert_match(/gold:50/, entry, 'the pouch holds fifty of the hundred')
    assert_equal 'gold+45', landing.last['fx'], 'the notice reports what actually landed'

    get "/games/#{BOOK}/hoard", params: { fx: 'gold+45' }
    assert_match 'Gold +45.', @response.body

    get "/games/#{BOOK}/hoard", params: { fx: 'stamina-4' }
    assert_match(%r{<span class='error'>Stamina -4\.</span>}, @response.body,
                 'a loss reads in red')

    pack 'camp', items: 'club,salve,meal:1', stats: 'skill:10,stamina:10,stamina_max:20,gold:5,gold_max:50'
    post '/games/turn', params: { book: BOOK, from: 'camp', choice: 0 }
    assert_match(/stamina:11/, entry, 'the meal is eaten and the salve mends one')
  end
end
