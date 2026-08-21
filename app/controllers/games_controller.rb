# frozen_string_literal: true

require 'gamebooks'
require 'dice'
require 'lone_wolf'

class GamesController < ApplicationController
  # No require_saved_location: the books ship with the app, so a reader without a
  # postcode spends nobody's rate limit here.

  # Hidden books stay off the shelf but keep their URLs and bookmarks: a reader
  # mid-story loses nothing, and unhiding is deleting one line of YAML.
  def index
    @books = Gamebooks.all.reject { |book| book['hidden'] }
  end

  # The book's own title page: begin a first read, or continue/restart one already
  # under way. The bookmark only counts if it still names a section — a book edit that
  # renames sections must not leave a continue link pointing nowhere.
  def book
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    saved = bookmarks[@book['id']].to_s.split('|').first
    @bookmark = saved if saved != @book['start'] && @book['sections'].key?(saved)
  end

  # A pure read: the bookmark and the stats move in #turn, never here, so a browser
  # that fetches links ahead of the cursor cannot turn pages the reader never chose.
  def section
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    @section = @book['sections'][params[:section]]
    if @section.nil?
      redirect_to games_book_path(book: @book['id'])
      return
    end

    return if @book['stats'].nil?

    @stats, @items, fight = unpack(bookmarks[@book['id']])
    @dead = @stats.present? && @stats.fetch(loss_stat(@book), 1) <= 0
    @combat = standing(@section, fight) if @section['combat']
  end

  # Every choice in a section posts here, named by its place in the section rather
  # than by its destination: the destination may hang on a dice test or a toll, and
  # those are the server's to apply. The bookmark — and for the books that keep them,
  # the stats and the satchel — are written and the reader is sent on to the
  # section's own GET, so the page being read keeps a plain URL that the back button,
  # a reload and the continue link can all fetch harmlessly.
  def turn
    book = Gamebooks.find(params[:book])
    if book.nil?
      redirect_to games_path
      return
    end

    from = book['sections'][params[:from]]
    return fight_round(book, from) if from && params[:choice] == 'fight' && from['combat']

    choice = from && from['choices'][params[:choice].to_i]
    if choice.nil?
      redirect_to games_book_path(book: book['id'])
      return
    end

    resolve(book, choice)
  end

  # A standing provision: what the satchel holds by count — meals, draughts — is
  # offered wherever the reader stands, spends itself when taken, and mends the stats
  # its entry says, without touching the page or its choices. Positive effects stop at
  # the rolled maximum: no meal makes a Kai mightier than the day he set out.
  def use
    book = Gamebooks.find(params[:book])
    provision = book&.dig('consumables', params[:item])
    if provision.nil?
      redirect_to games_path
      return
    end

    section, = bookmarks[book['id']].to_s.split('|')
    stats, items, fight = unpack(bookmarks[book['id']])
    unless usable?(book, section, stats, items)
      redirect_to games_book_path(book: book['id'])
      return
    end

    spend(items, params[:item])
    provision['effects'].each { |stat, delta| credit(stats, stat, delta) }
    remember(book, section, stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: section, used: params[:item])
  end

  # A provision is usable by the living, mid-story, with one in the satchel.
  def usable?(book, section, stats, items)
    section.present? && stats.present? &&
      stats.fetch(loss_stat(book), 0).positive? &&
      count_of(items, params[:item]).positive?
  end
  private :usable?

  # How many of a counted item the satchel holds. Entries ride as "meal:4"; a bare
  # name is one of it.
  def count_of(items, name)
    entry = items.find { |held| held == name || held.start_with?("#{name}:") }
    return 0 if entry.nil?

    entry.include?(':') ? entry.split(':').last.to_i : 1
  end
  helper_method :count_of

  # Starting again is forgetting: the bookmark and the character go together, and the
  # next turn out of the first page rolls a new one. A POST like every other move.
  def restart
    book = Gamebooks.find(params[:book])
    if book.nil?
      redirect_to games_path
      return
    end

    cookies.permanent['CYOA'] = bookmarks.except(book['id']).to_json
    redirect_to games_section_path(book: book['id'], section: book['start'])
  end

  private

  # The choice carried out: kit checked, tolls paid, dice thrown, the destination's
  # own effects applied, and the whole position written back as one cookie entry.
  def resolve(book, choice)
    stats, items = character(book)
    unless satisfied?(choice, stats, items)
      redirect_to games_section_path(book: book['id'], section: params[:from])
      return
    end

    (choice['cost'] || {}).each { |stat, price| stats[stat] -= price }
    rolled, destination = destination_of(choice, stats)
    apply_effects(book['sections'][destination], stats, items)

    remember(book, destination, stats, items)
    redirect_to games_section_path(book: book['id'], section: destination,
                                   rolled: rolled)
  end

  # One round of Lone Wolf combat: the ratio picks the column, a random number the
  # row, and both sides take what the table says. The enemy's remaining endurance
  # rides in the cookie beside the character; the round's numbers ride in the redirect
  # for the page to show, which keeps the section's GET a pure read.
  def fight_round(book, from)
    stats, items, fight = unpack(bookmarks[book['id']])
    foe, remaining = standing(from, fight)
    return redirect_to games_section_path(book: book['id'], section: params[:from]) if foe.nil?

    ratio = stats.fetch('skill', 0) + (items.include?('mindblast') ? 2 : 0) - foe['skill']
    number = rand(0..9)
    foe_loss, wolf_loss = LoneWolf.strike(ratio, number)

    remaining = foe_loss >= remaining ? 0 : remaining - foe_loss
    hurt = wolf_loss == LoneWolf::KILLED ? stats.fetch(loss_stat(book), 0) : wolf_loss
    stats[loss_stat(book)] = [stats.fetch(loss_stat(book), 0) - hurt, 0].max

    index = from['combat']['enemies'].index(foe)
    fight = remaining.positive? ? "#{index}:#{remaining}" : "#{index + 1}:next"
    remember(book, params[:from], stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: params[:from],
                                   rn: number, foe: foe_loss, you: hurt)
  end

  # Which enemy stands, and with how much left: the stored fight if one is under way,
  # otherwise the next enemy fresh from the book. nil when every enemy is down.
  def standing(section, fight)
    enemies = section['combat']['enemies']
    index, left = fight.to_s.split(':')
    index = index.to_i
    return [enemies[0], enemies[0]['endurance']] if fight.blank?
    return [enemies[index], left.to_i] if left != 'next' && enemies[index]

    enemies[index] ? [enemies[index], enemies[index]['endurance']] : nil
  end

  def loss_stat(book)
    book['dies_at_zero'] || 'endurance'
  end

  def satisfied?(choice, stats, items)
    return false if choice['needs'] && !items.include?(choice['needs'])

    (choice['cost'] || {}).all? { |stat, price| stats.fetch(stat, 0) >= price }
  end

  def destination_of(choice, stats)
    test = choice['test']
    return [nil, choice['to']] if test.nil?

    rolled = Dice.roll(test['roll'] || '2d6')
    [rolled, rolled <= stats.fetch(test['stat'], 0) ? test['win'] : test['lose']]
  end

  def apply_effects(section, stats, items)
    effects = section && section['effects']
    return if effects.nil?

    items << effects['take'] if effects['take'] && !items.include?(effects['take'])
    items.delete(effects['drop']) if effects['drop']
    effects.except('take', 'drop').each { |stat, delta| credit(stats, stat, delta) }
  end

  # A stat moved with its bounds respected: never below nothing, and gains stop at the
  # rolled maximum where the book keeps one.
  def credit(stats, stat, delta)
    value = stats.fetch(stat, 0) + delta
    cap = stats["#{stat}_max"]
    value = [value, cap].min if cap && delta.positive?
    stats[stat] = [value, 0].max
  end

  # One counted item off the string: "meal:4" becomes "meal:3", and the last one
  # leaves the satchel entirely.
  def spend(items, name)
    items.map! do |held|
      next held unless held == name || held.start_with?("#{name}:")

      left = count_of([held], name) - 1
      left.positive? ? "#{name}:#{left}" : nil
    end
    items.compact!
  end

  # The character as it stands — or, when the book holds none yet, rolled fresh from
  # the book's own dice. Restarting clears the entry (see #restart), which is what
  # makes the next turn a new character rather than the old one warmed over.
  def character(book)
    return [{}, []] if book['stats'].nil?

    stats, items = unpack(bookmarks[book['id']])
    return [stats, items] if stats.present?

    rolled = book['stats'].transform_values { |stat| Dice.roll(stat['start'].to_s) }
    # A stat marked max remembers the day it was rolled: gains stop there.
    book['stats'].each { |name, stat| rolled["#{name}_max"] = rolled[name] if stat['max'] }
    [rolled, outfit(book)]
  end

  def outfit(book)
    kit = Array(book['items']).dup
    if (draw = book['item_draw'])
      kit += draw['from'].sample(draw['count'])
    end
    (book['consumables'] || {}).each { |name, item| kit << "#{name}:#{item['start']}" }
    kit
  end

  def unpack(entry)
    _section, packed_stats, packed_items, fight = entry.to_s.split('|', 4)
    stats = packed_stats.to_s.split(',').to_h { |pair| pair.split(':').then { |k, v| [k, v.to_i] } }
    [stats, packed_items.to_s.split(','), fight.to_s]
  end

  def remember(book, destination, stats, items, fight = '')
    entry = if book['stats']
              packed = stats.map { |name, value| "#{name}:#{value}" }.join(',')
              "#{destination}|#{packed}|#{items.join(',')}|#{fight}"
            else
              destination
            end
    cookies.permanent['CYOA'] = bookmarks.merge(book['id'] => entry).to_json
  end

  # Reading progress lives in the CYOA cookie, one entry per book, client side like
  # every other setting.
  def bookmarks
    JSON.parse(cookies['CYOA'].presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
