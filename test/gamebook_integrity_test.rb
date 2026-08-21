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
              the-chasm-of-doom shadow-on-the-sand the-kingdoms-of-terror].freeze

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
        # A chit is the engine's own bookkeeping of picks owed, handed out on
        # carry-over rather than found in the story.
        here.include?(item) || item.start_with?('been to ', 'circle:') || item.end_with?(' choice')
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

  # "If you possess the Sommerswerd, turn to 304" was being offered to readers who
  # possessed no such thing, because the choice carried no gate. Every choice that
  # asks after something the reader might hold must actually check for it.
  ASKS = /\bif you (possess|have|are wearing|are carrying|still have|have ever been given)\b/i
  GATES = %w[needs without needs_any without_any rank rank_below when cost].freeze

  test 'a choice that asks what the reader carries actually checks for it' do
    Gamebooks.all.each do |book|
      known = catalogue(book)
      next if known.empty?

      ungated = book['sections'].flat_map do |id, section|
        (section['choices'] || []).filter_map do |choice|
          next if choice.keys.intersect?(GATES)
          next unless choice['label'].to_s.match?(ASKS)

          item = named_in(choice['label'], known)
          "#{id}: #{choice['label'][0, 60]}" if item
        end
      end

      assert_empty ungated, "#{book['id']}: possession asked about but never checked — #{ungated.inspect}"
    end
  end

  # Every sequel owes its returning reader the training the front matter promises —
  # "you may choose one extra Kai Discipline", and three Magnakai ones at the start of
  # the new arc. The engine used to deal that skill from the deck instead, and nothing
  # noticed, because the rule lives in the front matter rather than in any section.
  test 'every sequel lets the returning reader choose the skills the book grants them' do
    SERIES.each do |id|
      book = Gamebooks.find(id)
      next if book['sequel_of'].nil?

      chit = "#{book['learns'] || 'discipline'} choice"
      lesson = book['sections'].find { |_, section| Array(section['offers']).any? { |o| o['spends'] == chit } }
      assert lesson, "#{id}: nowhere to spend a #{chit}"

      offered = lesson.last['offers'].map { |offer| offer['item'] }
      teachable = Array(book.dig('item_draw', 'from')) - ['weaponskill']
      assert_empty teachable - offered, "#{id}: #{(teachable - offered).inspect} can never be learned"

      reachable = book['sections'].any? do |_, section|
        Array(section['choices']).any? { |choice| choice['to'] == lesson.first }
      end
      assert reachable, "#{id}: the #{lesson.first} page has no way in"
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

  # Everything this book has a name for and a reader might be holding.
  def catalogue(book)
    weapons = book['weapons'] || {}
    (Array(weapons['list']) + Array(weapons['kin']&.keys) + Array(weapons['special']&.keys) +
      (book['consumables'] || {}).keys + Array(book['worn']) +
      Array(book.dig('item_draw', 'from'))).uniq
  end

  # Whole words only, longest first: "axe" must not match inside "vaxeler".
  def named_in(label, known)
    known.sort_by { |name| -name.length }
         .find { |name| label.downcase.match?(/(?<![a-z])#{Regexp.escape(name)}(?![a-z])/) }
  end

  def assert_pick(book, sections, pick, where)
    if (compare = pick['compare'])
      %w[less more same].each do |branch|
        to = compare[branch]
        assert sections.key?(to), "#{book['id']} #{where}: compare #{branch} -> #{to}"
      end
      return
    end

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
               combat.dig('faltering', 'to'),
               combat.dig('duel', 'more'), combat.dig('duel', 'less'),
               combat.dig('duel', 'same')].compact
    targets.each { |to| assert sections.key?(to), "#{book['id']} #{id}: combat leads to #{to}" }
  end
end
