# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

# Building a Kai Lord step by step. The book throws for the scores, the Weaponskill
# weapon and the find among the ruins, so the wizard throws too and shows the number
# the Random Number Table gave — a reader who dislikes a throw may take another. The
# five disciplines are the reader's own choice, as the books say. Every step is a
# pure-read GET and every answer a POST, so nothing rerolls under a prefetching
# cursor.
class CharacterWizardTest < ActionDispatch::IntegrationTest
  BOOK = 'flight-from-the-dark'

  def answer(pick)
    post "/games/create/#{BOOK}", params: { pick: pick }
  end

  def page
    get "/games/create/#{BOOK}"
    @response.body
  end

  def sheet = JSON.parse(cookies['MAKE'].presence || '{}')

  def build_through_scores
    answer 'begin'
    answer 'accept'
    answer 'accept'
  end

  test 'the book offers the dice or the reader, and only where there is a sheet to build' do
    get "/games/#{BOOK}"
    assert_match I18n.t('games.begin'), @response.body
    assert_match I18n.t('games.make_character'), @response.body
    assert_match(%r{action="/games/create/#{BOOK}"}, @response.body,
                 'entering the wizard is a POST: a throw must never happen on a fetch')

    get '/games/treasure-hunt'
    assert_no_match(/#{I18n.t('games.make_character')}/, @response.body)
    get '/games/create/treasure-hunt'
    assert_redirected_to '/games'
  end

  test 'a score is thrown, shown with its dice, and may be thrown again' do
    answer 'begin'
    first = sheet['roll']
    assert_includes 10..19, first, 'Combat Skill is the table plus ten'

    body = page
    assert_match 'Combat Skill', body
    assert_match "#{I18n.t('games.make.rnt')} #{first - 10} + 10 = #{first}", body,
                 'the reader sees the number the table gave and what the rules add'
    assert_match I18n.t('games.make.accept'), body
    assert_match I18n.t('games.make.reroll'), body

    20.times do
      answer 'reroll'
      break if sheet['roll'] != first
    end
    assert_not_equal first, sheet['roll'], 'throwing again gives another number'
    assert_nil sheet['skill'], 'and nothing is committed until it is kept'

    kept = sheet['roll']
    answer 'accept'
    assert_equal kept, sheet['skill']
    assert_includes 20..29, sheet['roll'], 'Endurance is thrown next'
  end

  test 'reading the wizard never throws anything' do
    answer 'begin'
    before = sheet['roll']
    3.times { page }
    assert_equal before, sheet['roll'], 'a fetch leaves the dice alone'
  end

  test 'the disciplines are the reader own choice, explained in the book own words' do
    build_through_scores

    body = page
    assert_match 'You have mastered 5 of the ten Kai Disciplines', body
    assert_match 'blend in with his surroundings', body, 'Camouflage, as the book puts it'
    assert_match 'Hunting: no need for a Meal when instructed to eat', body
    assert_match 'Mindblast: +2 COMBAT SKILL points', body

    answer 'camouflage'
    assert_equal ['camouflage'], sheet['kai']
    answer 'flying'
    assert_equal ['camouflage'], sheet['kai'], 'a discipline that does not exist is no answer'
  end

  test 'choosing weaponskill asks for the weapon there and then, and throws for it' do
    build_through_scores
    answer 'weaponskill'

    assert_equal 'weapon', page[/Weaponskill/] ? 'weapon' : 'wrong step'
    assert_includes Gamebooks.find(BOOK)['weapons']['skill_table'], sheet['roll'],
                    'the weapon comes off the book own table'
    assert_equal 1, sheet['kai'].length, 'and it is asked before the next discipline'

    answer 'accept'
    assert_includes Gamebooks.find(BOOK)['weapons']['skill_table'], sheet['weapon']
    assert_match 'You have mastered', page, 'then the remaining disciplines'
  end

  test 'the find among the ruins is the book throw, not the reader pick' do
    build_through_scores
    ['camouflage', 'healing', 'sixth sense', 'mindshield', 'tracking'].each { |d| answer d }

    body = page
    assert_match I18n.t('games.make.kit_title'), body
    assert_match I18n.t('games.make.accept'), body
    assert_match I18n.t('games.make.reroll'), body
    table = Gamebooks.find(BOOK)['equipment_draw']
    assert_includes 0...table.length, sheet['roll'], 'one row of the equipment table'
    assert_no_match(/>3 /, body, 'no menu of every item to choose from')

    answer 'accept'
    assert_redirected_to "/games/#{BOOK}/start"
    section, stats, items = JSON.parse(cookies['CYOA'])[BOOK].split('|')
    rolled = stats.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }

    assert_equal 'start', section
    assert_includes 10..19, rolled['skill']
    assert_equal rolled['endurance_max'], rolled['endurance']
    held = items.split(',')
    assert_includes held, 'axe', 'the monastery axe comes as always'
    draw = Gamebooks.find(BOOK)['item_draw']['from']
    chosen = held.count { |i| draw.include?(i) || i.start_with?('weaponskill in ') }
    assert_equal 5, chosen, 'the five disciplines chosen, no more'
    assert_nil cookies['MAKE'].presence, 'the half-built sheet is put away'
  end

  test 'a sheet begun for one book is not muddled into another' do
    build_through_scores
    get '/games/create/fire-on-the-water'
    assert_no_match(/Combat Skill \d+ -/, @response.body,
                    'the other book starts from its own first question')
  end
end
