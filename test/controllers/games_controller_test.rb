# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

class GamesControllerTest < ActionDispatch::IntegrationTest
  # The books ship with the app: no saved location is required and nothing external is
  # ever requested, which WebMock's disable_net_connect! enforces across the suite.

  test 'lists the bundled books, minus the ones hidden from the shelf' do
    get '/games'

    assert_response :success
    assert_match 'Consider the Consequences!', @response.body
    assert_match 'Flight from the Dark', @response.body
    # Hidden, not gone: the shelf omits it while its URLs and bookmarks keep working.
    assert_no_match(/Treasure Hunt/, @response.body)

    get '/games/treasure-hunt'
    assert_response :success
  end

  test 'offers to begin a book not yet started' do
    get '/games/treasure-hunt'

    assert_response :success
    assert_match I18n.t('games.begin'), @response.body
    assert_no_match(/#{I18n.t('games.restart')}/, @response.body)
  end

  test 'offers continue and restart once a bookmark is saved' do
    post '/games/turn', params: { book: 'treasure-hunt', from: '1', choice: 0 }
    get '/games/treasure-hunt'

    assert_response :success
    assert_match I18n.t('common.continue'), @response.body
    assert_match I18n.t('games.restart'), @response.body
    assert_match '/games/treasure-hunt/5', @response.body
  end

  test 'ignores a bookmark that no longer names a section' do
    cookies['CYOA'] = { 'treasure-hunt' => 'gone' }.to_json

    get '/games/treasure-hunt'

    assert_match I18n.t('games.begin'), @response.body
  end

  test 'a bookmark at the very start still reads as a fresh book' do
    cookies['CYOA'] = { 'treasure-hunt' => '0' }.to_json
    get '/games/treasure-hunt'

    assert_match I18n.t('games.begin'), @response.body
  end

  test 'turning a page bookmarks it and lands on its plain URL, one entry per book' do
    post '/games/turn', params: { book: 'treasure-hunt', from: '1', choice: 0 }
    assert_redirected_to '/games/treasure-hunt/5'

    post '/games/turn', params: { book: 'consider-the-consequences', from: 'start', choice: 0 }

    saved = JSON.parse(cookies['CYOA'])
    assert_equal '5', saved['treasure-hunt']
    assert_equal 'Helen', saved['consider-the-consequences']
  end

  # Browsers that fetch links ahead of the cursor follow GETs the reader never chose,
  # so a read must never move the bookmark. Turning a page is games/turn's job.
  test 'reading a section does not move the bookmark' do
    get '/games/treasure-hunt/7'

    assert_response :success
    assert_nil cookies['CYOA'].presence
  end

  test 'shows a section with its text and numbered choices' do
    get '/games/treasure-hunt/1'

    assert_response :success
    assert_match 'two tall yew hedges', @response.body
    # Choices are text-only buttons, not links: nothing prefetches a page turn, and
    # nothing sits inside a button for the handset's cursor to stop on separately.
    # Each names its place in the section; the destination is the server's to decide.
    assert_equal 2, @response.body.scan(%r{action="/games/turn"}).size
    assert_match(/name="from"[^>]*value="1"|value="1"[^>]*name="from"/, @response.body)
    assert_match(/name="choice"[^>]*value="0"|value="0"[^>]*name="choice"/, @response.body)
    assert_match(/name="choice"[^>]*value="1"|value="1"[^>]*name="choice"/, @response.body)
    assert_match '/gamebooks/treasure-hunt/p1.jpg', @response.body
  end

  test 'every picture a section shows exists on disk' do
    Gamebooks.find('treasure-hunt')['sections'].each_value do |section|
      src = section.dig('image', 'src')
      next if src.nil?

      assert Rails.root.join("public#{src}").exist?, "missing picture #{src}"
    end
  end

  test 'a consequence without a destination is text rather than a link' do
    get '/games/treasure-hunt/2'

    assert_match 'they give up and go home', @response.body
    assert_no_match(/<a[^>]*>[^<]*give up and go home/, @response.body)
  end

  test 'an ending offers to start the book again' do
    ending = Gamebooks.find('consider-the-consequences')['sections']
                      .find { |_id, section| section['choices'].empty? }
                      .first

    get "/games/consider-the-consequences/#{ending}"

    assert_match I18n.t('games.the_end'), @response.body
    # Starting again is a POST: it forgets the bookmark and the character together.
    assert_match(%r{action="/games/restart"}, @response.body)
  end

  test 'sends an unknown book back to the shelf and an unknown section to its book' do
    get '/games/unknown'
    assert_redirected_to '/games'

    get '/games/treasure-hunt/999'
    assert_redirected_to '/games/treasure-hunt'

    post '/games/turn', params: { book: 'unknown', from: '1', choice: 0 }
    assert_redirected_to '/games'

    post '/games/turn', params: { book: 'treasure-hunt', from: '999', choice: 0 }
    assert_redirected_to '/games/treasure-hunt'
    assert_nil cookies['CYOA'].presence
  end

  test 'a garbled cookie is treated as no progress at all' do
    cookies['CYOA'] = 'not json'

    get '/games/treasure-hunt'
    assert_response :success
    assert_match I18n.t('games.begin'), @response.body

    post '/games/turn', params: { book: 'treasure-hunt', from: '1', choice: 0 }
    assert_equal({ 'treasure-hunt' => '5' }, JSON.parse(cookies['CYOA']))
  end

  # The stats layer, exercised on the fixture rig the test environment adds to the
  # shelf: rolled characters, kit, tolls, dice tests and effects. See engine-trial.yml.
  test 'a first turn out of a stat book rolls the character by its own dice' do
    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 0 }

    assert_redirected_to '/games/engine-trial/store'
    section, stats, items = JSON.parse(cookies['CYOA'])['engine-trial'].split('|')
    rolled = stats.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }

    assert_equal 'store', section
    assert_includes 7..12, rolled['skill']
    assert_includes 14..24, rolled['stamina']
    assert_equal 5, rolled['gold']
    assert_equal ['lamp', 'ration:2', 'rope'], items.split(','),
                 'the lamp and rations from the start, the rope from the store'
  end

  test 'kit gates a choice until it is carried' do
    cookies['CYOA'] = { 'engine-trial' => 'start|skill:8,stamina:14,gold:5|lamp' }.to_json

    get '/games/engine-trial/start'
    assert_match 'Skill 8', @response.body
    assert_match 'Carrying: lamp', @response.body
    assert_match 'needs the rope', @response.body

    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 2 }
    assert_redirected_to '/games/engine-trial/start'
    assert_equal 'start|skill:8,stamina:14,gold:5|lamp',
                 JSON.parse(cookies['CYOA'])['engine-trial'], 'a refused turn changes nothing'

    cookies['CYOA'] = { 'engine-trial' => 'start|skill:8,stamina:14,gold:5|lamp,rope' }.to_json
    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 2 }
    assert_redirected_to '/games/engine-trial/vault'
  end

  test 'a toll is paid from the stats or the gate stays shut' do
    cookies['CYOA'] = { 'engine-trial' => 'start|skill:8,stamina:14,gold:5|lamp' }.to_json
    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 1 }

    assert_redirected_to '/games/engine-trial/paid'
    assert_match 'gold:2', JSON.parse(cookies['CYOA'])['engine-trial']

    cookies['CYOA'] = { 'engine-trial' => 'start|skill:8,stamina:14,gold:2|lamp' }.to_json
    get '/games/engine-trial/start'
    assert_match 'not enough', @response.body

    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 1 }
    assert_redirected_to '/games/engine-trial/start'
  end

  test 'the dice decide a test, show their roll, and the landing takes its toll' do
    cookies['CYOA'] = { 'engine-trial' => 'start|skill:12,stamina:14,gold:5|lamp' }.to_json
    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 3 }

    assert_match %r{/games/engine-trial/across\?rolled=\d+}, @response.headers['Location'],
                 'two dice cannot beat a skill of twelve'

    cookies['CYOA'] = { 'engine-trial' => 'start|skill:1,stamina:14,gold:5|lamp' }.to_json
    post '/games/turn', params: { book: 'engine-trial', from: 'start', choice: 3 }

    assert_match %r{/games/engine-trial/fallen\?rolled=\d+}, @response.headers['Location'],
                 'two dice cannot land under a skill of one'
    assert_match 'stamina:12', JSON.parse(cookies['CYOA'])['engine-trial'],
                 'the fall costs the two stamina the section says'
  end

  # Combat, on the trial rig: a hopeless mismatch in each direction, so the table's
  # verdict is certain whatever the random number says.
  test 'a round of combat wears the enemy down and the win frees the choices' do
    cookies['CYOA'] = { 'engine-trial' => 'arena|skill:12,stamina:14,gold:5|lamp' }.to_json

    post '/games/turn', params: { book: 'engine-trial', from: 'arena', choice: 'fight' }

    assert_match %r{/games/engine-trial/arena\?}, @response.headers['Location']
    fight = JSON.parse(cookies['CYOA'])['engine-trial'].split('|', 4).last
    assert_equal '1:next', fight, 'a ratio of eleven or more fells five endurance in one round'

    get '/games/engine-trial/arena'
    assert_match 'The fight is won', @response.body
    assert_match 'Leave by the victors', @response.body
  end

  test 'combat can kill, and death ends the story wherever it stands' do
    cookies['CYOA'] = { 'engine-trial' => 'doom|skill:1,stamina:14,gold:5|lamp' }.to_json

    30.times do
      post '/games/turn', params: { book: 'engine-trial', from: 'doom', choice: 'fight' }
      break if JSON.parse(cookies['CYOA'])['engine-trial'].include?('stamina:0')
    end

    assert_match(/stamina:0/, JSON.parse(cookies['CYOA'])['engine-trial'],
                 'a giant at ratio minus eleven kills inside thirty rounds')

    get '/games/engine-trial/doom'
    assert_match I18n.t('games.the_end'), @response.body
    assert_match(%r{action="/games/restart"}, @response.body)
  end

  test 'the lone wolf shelf copy rolls a kai character by the book' do
    post '/games/turn', params: { book: 'flight-from-the-dark', from: 'start', choice: 0 }

    assert_redirected_to '/games/flight-from-the-dark/1'
    _section, stats, items = JSON.parse(cookies['CYOA'])['flight-from-the-dark'].split('|')
    rolled = stats.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }

    assert_includes 10..19, rolled['skill']
    assert_includes 20..29, rolled['endurance']
    assert_equal rolled['endurance'], rolled['endurance_max'],
                 'the endurance rolled is the ceiling meals mend towards'
    held = items.split(',')
    assert_equal 7, held.length, 'five disciplines, the meals and the potion'
    assert_includes held, 'meal:5'
    assert_includes held, 'laumspur:1'
  end

  # Provisions stand apart from the page: offered wherever the reader is, spending
  # themselves without moving the bookmark, mending only up to the rolled ceiling.
  test 'eating a ration mends the stat, spends the ration and leaves the page alone' do
    cookies['CYOA'] = { 'engine-trial' => 'paid|skill:8,stamina:10,stamina_max:14,gold:5|lamp,ration:2' }.to_json

    get '/games/engine-trial/paid'
    assert_match(/Eat a ration \(stamina \+3\) \(2 left\)/, @response.body)
    assert_match(/button[^>]*class="provision"/, @response.body,
                 'a provision reads apart from the book choices')

    post '/games/use', params: { book: 'engine-trial', item: 'ration' }

    assert_redirected_to '/games/engine-trial/paid?used=ration'
    assert_equal 'paid|skill:8,stamina:13,stamina_max:14,gold:5|lamp,ration:1|',
                 JSON.parse(cookies['CYOA'])['engine-trial']

    # The second one hits the ceiling: plus three stops at fourteen, and the last
    # ration leaves the satchel entirely.
    post '/games/use', params: { book: 'engine-trial', item: 'ration' }
    assert_equal 'paid|skill:8,stamina:14,stamina_max:14,gold:5|lamp|',
                 JSON.parse(cookies['CYOA'])['engine-trial']

    post '/games/use', params: { book: 'engine-trial', item: 'ration' }
    assert_redirected_to '/games/engine-trial', 'an empty satchel has nothing to use'
  end

  test 'provisions are not offered over a drawn blade or to the dead' do
    cookies['CYOA'] = { 'engine-trial' => 'arena|skill:8,stamina:10,stamina_max:14,gold:5|lamp,ration:2' }.to_json
    get '/games/engine-trial/arena'
    assert_no_match(/Eat a ration/, @response.body, 'no eating mid-combat')

    cookies['CYOA'] = { 'engine-trial' => 'paid|skill:8,stamina:0,stamina_max:14,gold:5|lamp,ration:2' }.to_json
    get '/games/engine-trial/paid'
    assert_no_match(/Eat a ration/, @response.body, 'no meal restores the dead')

    post '/games/use', params: { book: 'engine-trial', item: 'ration' }
    assert_redirected_to '/games/engine-trial'
    assert_match 'stamina:0', JSON.parse(cookies['CYOA'])['engine-trial']
  end

  test 'restarting forgets the bookmark and the character together' do
    cookies['CYOA'] = { 'engine-trial' => 'vault|skill:8,stamina:14,gold:2|lamp,rope' }.to_json
    post '/games/restart', params: { book: 'engine-trial' }

    assert_redirected_to '/games/engine-trial/start'
    assert_nil JSON.parse(cookies['CYOA'].presence || '{}')['engine-trial']
  end

  test 'every choice in every bundled book leads to a section that exists' do
    Gamebooks.all.each do |book|
      book['sections'].each do |id, section|
        section['choices'].each do |choice|
          targets = [choice['to'], choice.dig('test', 'win'), choice.dig('test', 'lose')].compact
          targets.each do |target|
            assert book['sections'].key?(target),
                   "#{book['id']} #{id} points at missing section #{target}"
          end
        end
      end
      assert book['sections'].key?(book['start']),
             "#{book['id']} start #{book['start']} is missing"
    end
  end
end
