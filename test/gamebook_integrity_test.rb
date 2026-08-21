# frozen_string_literal: true

require 'test_helper'
require 'gamebooks'

# The checks that hold a whole book together. Reading the prose section by section
# catches what a page says; these catch what a book cannot say — a door with no key
# anywhere behind it, a road to a page that does not exist.
#
# Written after a Red Pass that the story handed over but the engine never granted
# left readers standing at the harbour gate with nothing to show the guard.
class GamebookIntegrityTest < ActiveSupport::TestCase
  # In series order: an item found in an earlier book may be asked for in a later one.
  SERIES = %w[flight-from-the-dark fire-on-the-water the-caverns-of-kalte
              the-chasm-of-doom].freeze

  # Everything a reader can come to hold in this book.
  def obtainable(book)
    got = Array(book['items']).map { |item| item.split(':').first }
    got += Array(book.dig('item_draw', 'from'))
    got += (book['consumables'] || {}).keys
    got += Array(book['equipment_draw']).flat_map { |g| [g['item']] + (g['gain'] || {}).keys }
    book['sections'].each_value { |section| got += granted_by(section) }
    got.compact.uniq
  end

  def granted_by(section)
    got = Array(section['offers']).flat_map { |offer| [offer['item']] + Array(offer['with']) }
    effects = [section['effects']] + (section['choices'] || []).map { |c| c['effects'] }
    effects.compact.each do |fx|
      got += Array(fx['take'])
      got += (fx['gain'] || {}).keys
    end
    got
  end

  # Everything the book asks the reader to be holding.
  def demanded(book)
    book['sections'].flat_map do |id, section|
      gates = (section['choices'] || []).flat_map do |choice|
        [choice['needs'], choice['without']].compact +
          (Array(choice['needs_any']) + Array(choice['without_any'])).flatten
      end
      gates += combat_demands(section['combat'] || {})
      gates.compact.map { |item| [id, item] }
    end
  end

  def combat_demands(combat)
    forced = combat['arms'] unless ['bare hands', 'level', nil].include?(combat['arms'])
    [forced, combat.dig('drain', 'without')] +
      Array(combat['without']).filter_map { |rule| rule['item'] }
  end

  test 'every item a book asks for can be found somewhere by then' do
    carried = []
    SERIES.each do |id|
      book = Gamebooks.find(id)
      assert_not_nil book, "#{id} is missing"
      here = obtainable(book) + carried

      missing = demanded(book).reject do |_, item|
        here.include?(item) || item.start_with?('been to ')
      end.uniq

      assert_empty missing,
                   "#{id}: gated on items no reader can obtain — #{missing.inspect}"
      carried = here
    end
  end

  test 'every road in every book leads to a real page' do
    Gamebooks.all.each do |book|
      sections = book['sections']
      sections.each do |id, section|
        (section['choices'] || []).each do |choice|
          to = choice['to']
          assert sections.key?(to), "#{book['id']} #{id} -> #{to}" if to
          assert_pick(book, sections, choice['pick'], id) if choice['pick']
        end
        assert_combat(book, sections, section['combat'] || {}, id)
      end
    end
  end

  # Nothing may still be waiting on the reader to roll their own dice: every throw
  # the books make is the server's.
  test 'no book leaves a random number for the reader to pick' do
    Gamebooks.all.each do |book|
      left = book['sections'].select { |_, section| section['rnt'] }.keys
      assert_empty left, "#{book['id']} still asks the reader to pick a number: #{left.inspect}"
    end
  end

  private

  def assert_pick(book, sections, pick, where)
    pick['routes'].each do |route|
      landable = route['die'] || route['pick'] || sections.key?(route['to'])
      assert landable, "#{book['id']} #{where}: a pick route leads nowhere"
      assert_pick(book, sections, route['pick'], where) if route['pick']
    end
  end

  def assert_combat(book, sections, combat, id)
    targets = [combat['on_wound'], combat.dig('evade', 'to'), combat.dig('overtime', 'to'),
               combat.dig('win_within', 'to'), combat.dig('win_within', 'else'),
               combat.dig('contest', 'win'), combat.dig('contest', 'lose'),
               combat.dig('duel', 'more'), combat.dig('duel', 'less'),
               combat.dig('duel', 'same')].compact
    targets.each { |to| assert sections.key?(to), "#{book['id']} #{id}: combat leads to #{to}" }
  end
end
