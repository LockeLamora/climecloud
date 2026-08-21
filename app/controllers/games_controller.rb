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
    return unless @section['combat']

    @combat = standing(@section, fight)
    _, _, @round, = fight_parts(fight)
  end

  # Every choice in a section posts here, named by its place in the section rather
  # than by its destination: the destination may hang on a dice test, a toll or a
  # random pick, and those are the server's to apply. The bookmark — and for the books
  # that keep them, the stats and the satchel — are written and the reader is sent on
  # to the section's own GET, so the page being read keeps a plain URL that the back
  # button, a reload and the continue link can all fetch harmlessly.
  def turn
    book = Gamebooks.find(params[:book])
    if book.nil?
      redirect_to games_path
      return
    end

    from = book['sections'][params[:from]]
    return combat_move(book, from) if from && from['combat'] && %w[fight evade].include?(params[:choice])

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
  # the rolled maximum: no meal makes a Kai mightier than the day he set out. A battle
  # draught is the other way about: only mid-fight, and its virtue rides in the fight
  # rather than the stats, gone when the blades are put away.
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

    return swig(book, provision) if provision['battle']

    spend(items, params[:item])
    provision['effects'].each { |stat, delta| credit(stats, stat, delta) }
    remember(book, section, stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: section, used: params[:item])
  end

  # A standing offer: something the page says the reader may take. Taking it is a POST
  # that stays on the page, like a provision in reverse; the offer withdraws once the
  # thing is held, and a full weapon belt gives up its plainest arm to make room.
  def take
    book = Gamebooks.find(params[:book])
    if book.nil?
      redirect_to games_path
      return
    end

    section, = bookmarks[book['id']].to_s.split('|')
    stats, items, fight = unpack(bookmarks[book['id']])
    offer = Array(book.dig('sections', section, 'offers')).find { |entry| entry['item'] == params[:item] }
    unless offer && stats.present? && offer_open?(book, offer, items)
      redirect_to games_book_path(book: book['id'])
      return
    end

    gave = claim(book, offer, items)
    remember(book, section, stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: section,
                                   took: offer['item'], gave: gave)
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

  # An offer stands while the thing is not yet held, nothing it is barred by is held,
  # and — for an exchange — there is a weapon to give for it.
  def offer_open?(book, offer, items)
    held = offer['count'] ? count_of(items, offer['item']).positive? : items.include?(offer['item'])
    return false if held || Array(offer['unless']).any? { |other| items.include?(other) }

    !offer['swap'] || (items & weapons_list(book)).any?
  end
  helper_method :offer_open?

  # A stat gate on a choice: met when the stat sits inside the stated bounds. The view
  # hides the branch that does not apply — the page reads like the paper book, where
  # the reader simply follows the line that is true.
  def within?(rule, stats)
    return true if rule.nil?

    value = (stats || {}).fetch(rule['stat'], 0)
    value >= rule.fetch('at_least', value) && value <= rule.fetch('at_most', value)
  end
  helper_method :within?

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

  # The choice carried out: kit checked, tolls paid, dice thrown or the Random Number
  # Table picked, the destination's own effects applied, and the whole position
  # written back as one cookie entry.
  def resolve(book, choice)
    stats, items = character(book)
    unless satisfied?(choice, stats, items)
      redirect_to games_section_path(book: book['id'], section: params[:from])
      return
    end

    (choice['cost'] || {}).each { |stat, price| stats[stat] -= price }
    rolled, destination, luck = route_of(choice, stats)
    if destination == :death
      perish(book, stats, items)
      return
    end

    notices = luck.each_with_object({}) { |fortune, acc| acc.merge!(apply_effect_hash(fortune, book, stats, items)) }
    travel(book, destination, stats, items, rolled: rolled, notices: notices)
  end

  # Where the choice leads: straight on, through a stat test, or through the Random
  # Number Table. Returns the number shown to the reader, the destination, and any
  # effects the picked route carries with it.
  def route_of(choice, stats)
    return run_pick(choice['pick']) if choice['pick']

    test = choice['test']
    return [nil, choice['to'], []] if test.nil?

    rolled = Dice.roll(test['roll'] || '2d6')
    [rolled, rolled <= stats.fetch(test['stat'], 0) ? test['win'] : test['lose'], []]
  end

  # The Random Number Table, picked by the server so a reload cannot repick it: the
  # roll finds its route by range, a route may carry effects, chain into another pick
  # — the bog that takes three throws to escape — or simply be the end.
  def run_pick(pick, luck = [])
    rolled = Dice.roll(pick['roll'] || '1d10-1')
    route = pick['routes'].find { |r| rolled >= r.fetch('min', rolled) && rolled <= r.fetch('max', rolled) }
    luck << route['effects'] if route['effects']
    return [rolled, :death, luck] if route['die']
    return run_pick(route['pick'], luck) if route['pick']

    [rolled, route['to'], luck]
  end

  # A death written by the book rather than by wounds: the stat that measures life is
  # spent to nothing where the reader stands, and the page shows the end.
  def perish(book, stats, items)
    stats[loss_stat(book)] = 0
    remember(book, params[:from], stats, items)
    redirect_to games_section_path(book: book['id'], section: params[:from])
  end

  # The page turn itself: the destination's effects land, a healer mends on the way,
  # and the position is written back. The notices ride in the redirect for the page to
  # show, which keeps the section's GET a pure read.
  def travel(book, destination, stats, items, rolled: nil, notices: {})
    landing = book['sections'][destination]
    notices = notices.merge(apply_effects(book, landing, stats, items))
    mend(book, stats, items, landing)
    remember(book, destination, stats, items)
    redirect_to games_section_path(book: book['id'], section: destination,
                                   rolled: rolled, **notices.symbolize_keys)
  end

  # One round of combat: the ratio picks the column, a random number the row, and both
  # sides take what the table says. The enemy's remaining endurance, the round count
  # and any battle draught ride in the cookie beside the character; the round's
  # numbers ride in the redirect for the page to show.
  # The fight and its break-off, reached from #turn once the section is known to hold
  # a combat: fight throws a round; evade leaves it, where the book allows.
  def combat_move(book, from)
    return fight_round(book, from) if params[:choice] == 'fight'
    return evade_combat(book, from) if from['combat']['evade']

    redirect_to games_section_path(book: book['id'], section: params[:from])
  end

  def fight_round(book, from)
    stats, items, fight = unpack(bookmarks[book['id']])
    foe, remaining = standing(from, fight)
    return redirect_to games_section_path(book: book['id'], section: params[:from]) if foe.nil?

    _, _, round, buff = fight_parts(fight)
    number = rand(0..9)
    foe_loss, wolf_loss = LoneWolf.strike(combat_ratio(book, from, stats, items, fight), number)

    remaining = foe_loss >= remaining ? 0 : remaining - foe_loss
    hurt = wolf_loss == LoneWolf::KILLED ? stats.fetch(loss_stat(book), 0) : wolf_loss
    stats[loss_stat(book)] = [stats.fetch(loss_stat(book), 0) - hurt, 0].max

    index = from['combat']['enemies'].index(foe)
    fight = if remaining.positive?
              "#{index}:#{remaining}:#{round + 1}:#{buff}"
            else
              "#{index + 1}:next:#{round + 1}:#{buff}"
            end
    return if dragged_off?(book, from, stats, items, fight)

    remember(book, params[:from], stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: params[:from],
                                   rn: number, foe: foe_loss, you: hurt)
  end

  # The fight the book will not let run on: still standing when the stated round ends,
  # the reader is dragged to the section the book names instead of fighting on.
  def dragged_off?(book, from, stats, items, fight)
    overtime = from['combat']['overtime']
    _, _, round, = fight_parts(fight)
    return false unless overtime && round >= overtime['rounds']
    return false unless standing(from, fight) && stats.fetch(loss_stat(book), 0).positive?

    travel(book, overtime['to'], stats, items)
    true
  end

  # Breaking off a fight the book allows to be broken, once enough rounds have been
  # stood. The escape section's own effects land as on any other page turn.
  def evade_combat(book, from)
    rule = from['combat']['evade']
    stats, items, fight = unpack(bookmarks[book['id']])
    _, _, round, = fight_parts(fight)
    if stats.blank? || round < rule.fetch('after', 0)
      redirect_to games_section_path(book: book['id'], section: params[:from])
      return
    end

    travel(book, rule['to'], stats, items)
  end

  # The attack ratio, with everything the book lays on it: the flat modifier, the
  # surprise that lasts one round, penalties that apply without a named item (a
  # torch in the dark, Mindshield against a Mindforce), a battle draught's virtue,
  # Mindblast unless this enemy shrugs it, and the weapon in hand.
  def combat_ratio(book, from, stats, items, fight)
    combat = from['combat']
    foe, = standing(from, fight)
    _, _, round, buff = fight_parts(fight)

    ratio = stats.fetch('skill', 0) - foe['skill'] + buff + combat.fetch('modifier', 0)
    ratio += combat['surprise'].to_i if round.zero?
    ratio += 2 if items.include?('mindblast') && !Array(combat['immune']).include?('mindblast')
    Array(combat['without']).each { |rule| ratio += rule['modifier'] unless items.include?(rule['item']) }
    ratio + weapon_bonus(book, items)
  end

  # Bare hands cost the book's stated penalty; the weapon Weaponskill was learned in
  # earns its bonus while one is held. Books without a weapons table are unmoved.
  def weapon_bonus(book, items)
    rules = book['weapons']
    return 0 if rules.nil?

    held = rules['list'] & items
    return rules.fetch('unarmed', -4) if held.empty?

    skilled = items.filter_map { |entry| entry[/\Aweaponskill in (.+)\z/, 1] }.first
    held.include?(skilled) ? rules.fetch('bonus', 2) : 0
  end

  # Which enemy stands, and with how much left: the stored fight if one is under way,
  # otherwise the next enemy fresh from the book. nil when every enemy is down.
  def standing(section, fight)
    enemies = section['combat']['enemies']
    index, left, = fight.to_s.split(':')
    index = index.to_i
    return [enemies[0], enemies[0]['endurance']] if fight.blank?
    return [enemies[index], left.to_i] if left != 'next' && enemies[index]

    enemies[index] ? [enemies[index], enemies[index]['endurance']] : nil
  end

  # The fight string unpacked: enemy index, endurance left, rounds fought this
  # combat, and any battle draught's bonus. Older cookies carried only the first two;
  # the missing fields read as zero.
  def fight_parts(fight)
    index, left, round, buff = fight.to_s.split(':')
    [index.to_i, left, round.to_i, buff.to_i]
  end

  # A battle draught: spent mid-fight, its bonus rides in the fight string and is
  # forgotten with it when the fight — or the section — ends.
  def swig(book, provision)
    section, = bookmarks[book['id']].to_s.split('|')
    stats, items, fight = unpack(bookmarks[book['id']])
    combat = book.dig('sections', section, 'combat')
    if combat.nil? || standing(book['sections'][section], fight).nil?
      redirect_to games_section_path(book: book['id'], section: section)
      return
    end

    spend(items, params[:item])
    index, left, round, buff = fight_parts(fight)
    left = standing(book['sections'][section], fight).last if fight.blank?
    fight = "#{index}:#{left}:#{round}:#{buff + provision['battle'].values.sum}"
    remember(book, section, stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: section, used: params[:item])
  end

  def loss_stat(book)
    book['dies_at_zero'] || 'endurance'
  end

  # needs bars a choice without the named item; without bars it while the item is
  # held (the "if you do not possess" branch of a paper fork); when bars it by stat.
  def satisfied?(choice, stats, items)
    kit_allows?(choice, items) && within?(choice['when'], stats) &&
      (choice['cost'] || {}).all? { |stat, price| stats.fetch(stat, 0) >= price }
  end

  def kit_allows?(choice, items)
    return false if choice['needs'] && !items.include?(choice['needs'])

    choice['without'].nil? || !items.include?(choice['without'])
  end

  def apply_effects(book, section, stats, items)
    effects = section && section['effects']
    return {} if effects.nil?

    apply_effect_hash(effects, book, stats, items)
  end

  # The keys that move things rather than numbers; everything else in an effects hash
  # is a stat and its delta.
  KIT_EFFECTS = %w[take drop gain steal drop_weapons drop_backpack must_eat risk].freeze

  def apply_effect_hash(effects, book, stats, items)
    notices = shift_kit(effects, book, items)
    notices[:ate] = eat(book, stats, items) if effects['must_eat']
    risk(effects['risk'], book, stats, items, notices) if effects['risk']
    effects.except(*KIT_EFFECTS).each { |stat, delta| credit(stats, stat, delta) }
    notices
  end

  # The satchel side of an effects hash: things taken, dropped, gained by the
  # handful, stolen, or lost wholesale.
  def shift_kit(effects, book, items)
    swap_kit(effects, items)
    notices = {}
    notices[:lost] = steal(book, items) if effects['steal']
    items.reject! { |held| weapons_list(book).include?(held) } if effects['drop_weapons']
    strip_backpack(book, items) if effects['drop_backpack']
    notices
  end

  def swap_kit(effects, items)
    items << effects['take'] if effects['take'] && !items.include?(effects['take'])
    items.delete(effects['drop']) if effects['drop']
    (effects['gain'] || {}).each { |name, extra| add_count(items, name, extra) }
  end

  # A throw of the Random Number Table inside an effects hash: the bolt that may or
  # may not hit. One branch of effects lands, by the roll.
  def risk(rule, book, stats, items, notices)
    rolled = Dice.roll(rule['roll'] || '1d10-1')
    hit = rolled >= rule.fetch('at_least', rolled) && rolled <= rule.fetch('at_most', rolled)
    branch = hit ? rule['then'] : rule['else']
    notices.merge!(apply_effect_hash(branch, book, stats, items)) if branch
  end

  # The book has said "you must now eat": Hunting feeds the hunter for nothing, a
  # Meal is eaten from the satchel, Laumspur serves as one (and heals as it always
  # does), and an empty satchel costs the hungry what the rules say.
  def eat(book, stats, items)
    return 'hunting' if items.include?('hunting')
    return 'meal' if spend(items, 'meal')

    if spend(items, 'laumspur')
      (book.dig('consumables', 'laumspur', 'effects') || {}).each { |stat, delta| credit(stats, stat, delta) }
      'laumspur'
    else
      stats[loss_stat(book)] = [stats.fetch(loss_stat(book), 0) - 3, 0].max
      'nothing'
    end
  end

  # One thing lifted from the backpack — or, with the pack empty, a weapon off the
  # belt, exactly as the book threatens. Disciplines and what is worn cannot be taken.
  def steal(book, items)
    pool = backpack_items(book, items)
    pool = items & weapons_list(book) if pool.empty?
    taken = pool.sample
    return 'nothing' if taken.nil?

    spend(items, taken)
    taken
  end

  # What rides in the backpack: everything that is not a weapon, a discipline, or
  # worn. Counted entries answer to their bare name.
  def backpack_items(book, items)
    keep = weapons_list(book) + Array(book['worn']) + Array(book.dig('item_draw', 'from'))
    items.filter_map do |held|
      name = held.split(':').first
      name unless keep.include?(name) || held.start_with?('weaponskill in ')
    end
  end

  def strip_backpack(book, items)
    backpack_items(book, items).each do |name|
      items.reject! { |held| held == name || held.start_with?("#{name}:") }
    end
  end

  def weapons_list(book)
    book.dig('weapons', 'list') || []
  end

  # A stat moved with its bounds respected: never below nothing, and gains stop at the
  # rolled maximum where the book keeps one.
  def credit(stats, stat, delta)
    value = stats.fetch(stat, 0) + delta
    cap = stats["#{stat}_max"]
    value = [value, cap].min if cap && delta.positive?
    stats[stat] = [value, 0].max
  end

  # The Kai Discipline of Healing, or whatever a book calls it: each page turned
  # while no fight is on mends a point, up to the rolled maximum.
  def mend(book, stats, items, section)
    rule = book['healing']
    return if rule.nil? || section.nil? || section['combat'] || !items.include?(rule['item'])

    credit(stats, rule['stat'], rule['delta'])
  end

  # One counted item off the string: "meal:4" becomes "meal:3", and the last one
  # leaves the satchel entirely. Returns whether there was one to spend.
  def spend(items, name)
    had = count_of(items, name).positive?
    items.map! do |held|
      next held unless held == name || held.start_with?("#{name}:")

      left = count_of([held], name) - 1
      left.positive? ? "#{name}:#{left}" : nil
    end
    items.compact!
    had
  end

  def add_count(items, name, extra)
    total = count_of(items, name) + extra
    items.reject! { |held| held == name || held.start_with?("#{name}:") }
    items << "#{name}:#{total}"
  end

  # Taking an offer up: counted things join their pile; a weapon may cost the belt
  # its plainest arm — the one Weaponskill was not learned in — either because the
  # offer is an exchange or because two are already carried.
  def claim(book, offer, items)
    return add_count(items, offer['item'], offer['count']) && nil if offer['count']

    gave = make_room(book, offer, items)
    items << offer['item']
    gave
  end

  def make_room(book, offer, items)
    held = items & weapons_list(book)
    return nil unless weapons_list(book).include?(offer['item'])
    return nil if held.empty? || (held.length < 2 && !offer['swap'])

    skilled = items.filter_map { |entry| entry[/\Aweaponskill in (.+)\z/, 1] }.first
    discard = (held - [skilled]).first || held.first
    items.delete(discard)
    discard
  end

  # The character as it stands — or, when the book holds none yet, rolled fresh from
  # the book's own dice: stats with their maximums and caps, disciplines drawn,
  # Weaponskill given its weapon, and the starting equipment table thrown.
  def character(book)
    return [{}, []] if book['stats'].nil?

    stats, items = unpack(bookmarks[book['id']])
    return [stats, items] if stats.present?

    rolled = book['stats'].transform_values { |stat| Dice.roll(stat['start'].to_s) }
    book['stats'].each do |name, stat|
      rolled["#{name}_max"] = rolled[name] if stat['max']
      rolled["#{name}_max"] = stat['cap'] if stat['cap']
    end
    items = outfit(book)
    endow(book, rolled, items)
    [rolled, items]
  end

  def outfit(book)
    kit = Array(book['items']).dup
    if (draw = book['item_draw'])
      kit += draw['from'].sample(draw['count'])
    end
    if kit.delete('weaponskill') && (table = book.dig('weapons', 'skill_table'))
      kit << "weaponskill in #{table.sample}"
    end
    (book['consumables'] || {}).each do |name, item|
      kit << "#{name}:#{item['start']}" if item['start'].to_i.positive?
    end
    kit
  end

  # The starting equipment table: one throw, one grant — an item, a handful of
  # something counted, or a stat bonus that raises the rolled maximum with it.
  def endow(book, stats, items)
    table = book['equipment_draw']
    return if table.nil?

    grant = table.sample
    items << grant['item'] if grant['item']
    (grant['gain'] || {}).each { |name, extra| add_count(items, name, extra) }
    grant.except('item', 'gain').each { |stat, delta| boost(book, stats, stat, delta) }
  end

  # A grant that adds to a rolled stat raises the rolled maximum with it: the helmet
  # is worn from the first day, so the ceiling was never lower.
  def boost(book, stats, stat, delta)
    stats["#{stat}_max"] += delta if stats.key?("#{stat}_max") && book.dig('stats', stat, 'max')
    stats[stat] = stats.fetch(stat, 0) + delta
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
