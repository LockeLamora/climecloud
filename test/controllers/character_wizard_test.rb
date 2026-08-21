# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

# Building a Kai Lord by hand instead of by dice: every score, discipline and item
# chosen, each explained in the book's own words. Every step is a pure-read GET and
# every answer a POST, as everything else in the games section is.
class CharacterWizardTest < ActionDispatch::IntegrationTest
  BOOK = 'flight-from-the-dark'

  def answer(pick)
    post "/games/create/#{BOOK}", params: { pick: pick }
  end

  def page
    get "/games/create/#{BOOK}"
    @response.body
  end

  test 'the book offers the dice or the reader, and only offers the wizard for books with disciplines' do
    get "/games/#{BOOK}"
    assert_match I18n.t('games.begin'), @response.body
    assert_match I18n.t('games.make_character'), @response.body

    get '/games/treasure-hunt'
    assert_no_match(/#{I18n.t('games.make_character')}/, @response.body,
                    'a book without a character sheet has nothing to build')

    get '/games/create/treasure-hunt'
    assert_redirected_to '/games'
  end

  test 'each step explains itself in the book own words' do
    assert_match 'Combat Skill', page
    assert_match '>1 10<', page, 'the ten scores the dice could have given'
    assert_match '>10 19<', page

    answer 17
    assert_match 'Endurance', page
    assert_match '>1 20<', page

    answer 25
    body = page
    assert_match 'Combat Skill 17 - Endurance 25', body, 'the sheet so far'
    assert_match 'You have mastered 5 of the ten Kai Disciplines', body
    # The disciplines are described, and the four with a rule state it.
    assert_match 'blend in with his surroundings', body, 'Camouflage, as the book puts it'
    assert_match 'Hunting: no need for a Meal when instructed to eat', body
    assert_match 'Mindblast: +2 COMBAT SKILL points', body
  end

  test 'a character built by hand starts the story exactly as chosen' do
    answer 17
    answer 25
    ['weaponskill', 'healing', 'sixth sense', 'mindshield', 'camouflage'].each { |d| answer d }

    assert_match '>6 Sword<', page, 'the weapon it was learned in is asked for next'

    answer 'sword'
    assert_match 'Adds 4 ENDURANCE points', page, 'the waistcoat explains itself'

    chainmail = Gamebooks.find(BOOK)['equipment_draw'].index { |g| g['item'] == 'chainmail waistcoat' }
    answer chainmail

    assert_redirected_to "/games/#{BOOK}/start"
    section, stats, items = JSON.parse(cookies['CYOA'])[BOOK].split('|')
    rolled = stats.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }

    assert_equal 'start', section
    assert_equal 17, rolled['skill'], 'the score chosen, not a rolled one'
    assert_equal [29, 29], [rolled['endurance'], rolled['endurance_max']],
                 'twenty-five chosen, and the waistcoat lifts both by four'
    held = items.split(',')
    assert_includes held, 'weaponskill in sword'
    assert_includes held, 'chainmail waistcoat'
    assert_includes held, 'axe', 'the monastery axe comes as always'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    chosen = held.count { |i| draw.include?(i) || i.start_with?('weaponskill in ') }
    assert_equal 5, chosen, 'the five disciplines chosen, no more'
    assert_nil cookies['MAKE'].presence, 'the half-built sheet is put away'
  end

  test 'the wizard refuses answers that are not on offer and keeps its place' do
    answer 99
    assert_match 'Combat Skill', page, 'a score off the table is no answer at all'

    answer 12
    answer 21
    answer 'flying'
    body = page
    assert_match 'You have mastered', body, 'and neither is a discipline that does not exist'
    assert_no_match(/Disciplines: /, body, 'nothing was recorded')
  end

  test 'a sheet begun for one book is not muddled into another' do
    answer 17
    answer 25
    get '/games/create/fire-on-the-water'
    assert_match 'Combat Skill', @response.body, 'the other book starts from its own first question'
    assert_no_match(/Combat Skill 17/, @response.body)
  end
end
