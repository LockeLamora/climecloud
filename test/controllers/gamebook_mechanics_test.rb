# frozen_string_literal: true

require 'test_helper'
require 'lone_wolf'
require 'gamebooks'

# The mechanics the 2026-08-21 word-by-word audit of all three books added, proven
# against the real pages that needed them.
class GamebookMechanicsTest < ActionDispatch::IntegrationTest
  def pack(book, section, stats:, items: '', fight: '')
    cookies['CYOA'] = { book => "#{section}|#{stats}|#{items}|#{fight}" }.to_json
  end

  def entry(book) = JSON.parse(cookies['CYOA'])[book]

  def landing
    query = Rack::Utils.parse_query(URI(@response.headers['Location']).query.to_s)
    [URI(@response.headers['Location']).path, query]
  end

  def fight(book, from)
    post '/games/turn', params: { book: book, from: from, choice: 'fight' }
  end

  # Section 283: "add 2 points for the first round of combat only... unless you have
  # Mindshield, deduct 2 for the second and subsequent rounds."
  test 'a penalty that starts on the second round leaves the first one alone' do
    book = 'flight-from-the-dark'
    kit = 'skill:17,endurance:30,endurance_max:30,gold:5,gold_max:50'

    pack(book, '283', stats: kit, items: 'axe')
    get "/games/#{book}/283"
    assert_match 'Attack ratio +2.', @response.body, 'first round: the surprise, no Mindforce yet'

    pack(book, '283', stats: kit, items: 'axe', fight: '0:25:1:0:30')
    get "/games/#{book}/283"
    assert_match 'Attack ratio -2.', @response.body, 'second round: the Mindforce bites'

    pack(book, '283', stats: kit, items: 'axe,mindshield', fight: '0:25:1:0:30')
    get "/games/#{book}/283"
    assert_match 'Attack ratio +0.', @response.body, 'Mindshield turns the Mindforce aside'
  end

  # Section 158: a scout on skis, one exchange, and whoever came off worse decides it.
  test 'a passing duel is settled by one exchange' do
    book = 'the-caverns-of-kalte'
    pack(book, '158', stats: 'skill:20,endurance:40,endurance_max:40,gold:5,gold_max:50',
                      items: 'sword')

    fight(book, '158')
    path, = landing
    assert_includes %w[165 271 337].map { |id| "/games/#{book}/#{id}" }, path,
                    'one exchange and the scout is past: the road is already decided'
    assert_match(/^(165|271|337)\|/, entry(book), 'the fight does not carry on')
  end

  # Section 180: "Deduct an additional 3 ENDURANCE points from the Kalkoth for each
  # round of combat you fight. This represents the damage inflicted by Fenor."
  test 'a companion lands blows of their own each round' do
    book = 'the-caverns-of-kalte'
    pack(book, '180', stats: 'skill:1,endurance:80,endurance_max:80,gold:5,gold_max:50')

    # Any wound sends the reader off to 129, so keep trying until a round lands
    # unscathed and the numbers can be read.
    scored = nil
    12.times do
      # A plain sword, so the ratio is simply skill against the Kalkoth's eleven.
      pack(book, '180', stats: 'skill:1,endurance:80,endurance_max:80,gold:5,gold_max:50',
                        items: 'sword')
      fight(book, '180')
      _, query = landing
      next if query['rn'].blank?

      table, = LoneWolf.strike(1 - 11, query['rn'].to_i)
      scored = [table + 3, query['foe'].to_i]
      break
    end

    assert_not_nil scored, 'no unscathed round in twelve tries'
    assert_equal scored.first, scored.last, "Fenor's three land alongside yours"
  end

  # Section 306: "Fight the following combat as normal, but double all ENDURANCE
  # points lost by the enemy" — a living guard, so the Sommerswerd is not the reason.
  test 'a fight the book says is doubled is doubled without any sword of the sun' do
    book = 'fire-on-the-water'
    pack(book, '306', stats: 'skill:16,endurance:30,endurance_max:30,gold:5,gold_max:50',
                      items: 'sword')

    fight(book, '306')
    _, query = landing
    table, = LoneWolf.strike(0, query['rn'].to_i)
    expected = table >= LoneWolf::KILLED ? table : table * 2
    assert_equal expected, query['foe'].to_i
  end

  # The book's rule: "you may restore 1 ENDURANCE point for every numbered section
  # you pass through in which you are not involved in combat... your ENDURANCE cannot
  # rise above its original level." Not a thing to spend, then: it simply happens as
  # the pages turn, and only on quiet ones.
  test 'healing mends a point per quiet page, never in a fight, never past the ceiling' do
    book = 'flight-from-the-dark'
    hurt = 'skill:15,endurance:20,endurance_max:25,gold:5,gold_max:50'

    # A quiet page turn: one point back.
    pack(book, '1', stats: hurt, items: 'axe,healing')
    post '/games/turn', params: { book: book, from: '1', choice: 1 }
    assert_match(/endurance:21/, entry(book), 'a quiet section mends one')

    # The same turn without the discipline mends nothing.
    pack(book, '1', stats: hurt, items: 'axe')
    post '/games/turn', params: { book: book, from: '1', choice: 1 }
    assert_match(/endurance:20/, entry(book), 'no discipline, no mending')

    # Arriving at a fight mends nothing, discipline or not.
    from = Gamebooks.find(book)['sections'].find do |_, s|
      (s['choices'] || []).any? { |c| Gamebooks.find(book)['sections'].dig(c['to'].to_s, 'combat') }
    end
    fighty = from.last['choices'].index { |c| Gamebooks.find(book)['sections'].dig(c['to'].to_s, 'combat') }
    pack(book, from.first, stats: hurt, items: 'axe,healing')
    post '/games/turn', params: { book: book, from: from.first, choice: fighty }
    assert_match(/endurance:2[01]/, entry(book), 'no mending on a page where blades are out')
    assert_no_match(/endurance:22/, entry(book))

    # And it never lifts a Kai Lord above the score they set out with.
    pack(book, '1', stats: 'skill:15,endurance:25,endurance_max:25,gold:5,gold_max:50',
                    items: 'axe,healing')
    post '/games/turn', params: { book: book, from: '1', choice: 1 }
    assert_match(/endurance:25/, entry(book), 'the ceiling holds')

    # Standing still — eating, taking — is not passing through a section.
    pack(book, '1', stats: hurt, items: 'axe,healing,meal:1')
    post '/games/use', params: { book: book, item: 'meal' }
    assert_match(/endurance:23/, entry(book), 'the meal alone: three, not four')
  end

  # The set-up reads once. It stayed hidden while blades were out, but came back the
  # moment the last enemy fell — which in a long fight is every few turns — so a
  # reader saw the whole chapter again and again. It now stays away until the reader
  # arrives afresh.
  test 'a fight shows its numbers only, from the first round to after the last' do
    book = 'the-chasm-of-doom'
    section = '208' # three tunnel guards, so the fight runs on
    opening = Gamebooks.find(book)['sections'][section]['text'][0, 40]
    kit = 'skill:19,endurance:90,endurance_max:90,gold:5,gold_max:50'

    pack(book, section, stats: kit, items: 'sword')
    get "/games/#{book}/#{section}"
    assert_match opening, @response.body, 'the set-up shows on arrival'

    won = false
    12.times do
      fight(book, section)
      break unless URI(@response.headers['Location']).path.end_with?("/#{section}")

      follow_redirect!
      assert_no_match(/#{Regexp.escape(opening)}/, @response.body,
                      'the prose must not come back mid-fight')
      won = @response.body.include?('The fight is won')
      break if won
    end

    assert won, 'the fight should have been won inside twelve rounds'
    assert_no_match(/#{Regexp.escape(opening)}/, @response.body,
                    'nor when the last enemy falls')
  end

  # Kalte's section 16: "two separate items have been crushed and must be discarded
  # here." Proven on the rig, where the pack's contents are known exactly.
  test 'a crushing door takes exactly two things out of the pack' do
    book = 'war-rig'
    pack(book, 'camp', stats: 'skill:10,stamina:20,stamina_max:20,gold:5,gold_max:50',
                       items: 'club,salve,tonic:1,meal:2,laumspur:1')
    choice = Gamebooks.find(book)['sections']['camp']['choices'].index { |c| c['to'] == 'crush' }

    post '/games/turn', params: { book: book, from: 'camp', choice: choice }

    held = entry(book).split('|')[2].split(',').map { |h| h.split(':').first }
    assert_includes held, 'club', 'a weapon rides on the belt, not in the pack'
    assert_equal 2, (%w[salve tonic meal laumspur] & held).length,
                 'two of the four pack items are crushed, and only two'
  end

  # The Caverns of Kalte asks whether the reader has ever seen places from the
  # earlier books; the marker is left by the page that shows them.
  test 'a place seen in an earlier book is remembered in a later one' do
    b1 = Gamebooks.find('flight-from-the-dark')['sections']['329']
    assert_includes Array(b1.dig('effects', 'take')), 'been to the graveyard'

    book = 'the-caverns-of-kalte'
    kit = 'skill:15,endurance:25,endurance_max:25,gold:5,gold_max:50'
    pack(book, '268', stats: kit, items: 'sword')
    get "/games/#{book}/268"
    assert_no_match(%r{action="/games/turn"[^>]*>[^!]*?value="0"}m, @response.body,
                    'a stranger to the Graveyard is never offered that branch')
    assert_no_match(/needs the been to/, @response.body, 'and is not nagged about it')

    pack(book, '268', stats: kit, items: 'sword,been to the graveyard')
    get "/games/#{book}/268"
    assert_match '177', @response.body, 'the reader who stood there recognises the smell'
    assert_no_match(/Carrying[^<]*been to/, @response.body, 'a memory is not baggage')
  end
end
