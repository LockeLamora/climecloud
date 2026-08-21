# frozen_string_literal: true

require 'gamebooks'
require 'dice'
require 'lone_wolf'

class GamesController < ApplicationController
  # No require_saved_location: the books ship with the app, so a reader without a
  # postcode spends nobody's rate limit here.

  # Hidden books stay off the shelf but keep their URLs and bookmarks: a reader
  # mid-story loses nothing, and unhiding is deleting one line of YAML. Books that
  # belong to a series appear as one shelf entry — the series page lists its volumes.
  def index
    seen = []
    @shelf = Gamebooks.all.reject { |book| book['hidden'] }.filter_map do |book|
      next book if book['series'].nil?
      next if seen.include?(book['series'])

      seen << book['series']
      { 'series' => book['series'] }
    end
  end

  # A series' own page: its volumes in order, each led by its number in the series.
  def series
    books = Gamebooks.all.reject { |book| book['hidden'] }
    @books = books.select { |book| book['series'].to_s.parameterize == params[:name] }
    redirect_to games_path if @books.empty?
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
    @fight = fight
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
    unless offer && stats.present? && offer_open?(book, offer, items, stats)
      redirect_to games_book_path(book: book['id'])
      return
    end

    gave = claim(book, offer, stats, items)
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
  # its price and its chits (see 'spends') can be met, and — for an exchange — there
  # is a weapon to give for it.
  def offer_open?(book, offer, items, stats = {})
    return false if offer_held?(offer, items) || Array(offer['unless']).any? { |other| items.include?(other) }
    return false unless affordable?(offer, items, stats)

    !offer['swap'] || (items & weapons_list(book)).any?
  end
  helper_method :offer_open?

  # A counted offer that spends a chit — the armoury's pick-any-two — never reads as
  # already held: the chits are what limits it.
  def offer_held?(offer, items)
    return false if offer['count'] && offer['spends']

    offer['count'] ? count_of(items, offer['item']).positive? : items.include?(offer['item'])
  end

  def affordable?(offer, items, stats)
    return false if offer['spends'] && count_of(items, offer['spends']).zero?

    offer['price'].nil? || (stats || {}).fetch('gold', 0) >= offer['price']
  end

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
    notices = choice['effects'] ? apply_effect_hash(choice['effects'], book, stats, items) : {}
    rolled, destination, luck = route_of(book, choice, stats, items)
    if destination == :death
      perish(book, stats, items)
      return
    end

    luck.each { |fortune| merge_notices(notices, apply_effect_hash(fortune, book, stats, items)) }
    travel(book, destination, stats, items, rolled: rolled, notices: notices)
  end

  # Where the choice leads: straight on, through a stat test, or through the Random
  # Number Table. Returns the number shown to the reader, the destination, and any
  # effects the picked route carries with it.
  def route_of(book, choice, stats, items)
    return run_pick(book, choice['pick'], stats, items) if choice['pick']

    test = choice['test']
    return [nil, choice['to'], []] if test.nil?

    rolled = Dice.roll(test['roll'] || '2d6')
    [rolled, rolled <= stats.fetch(test['stat'], 0) ? test['win'] : test['lose'], []]
  end

  # The Random Number Table, picked by the server so a reload cannot repick it: the
  # roll finds its route by range — a discipline or the state of the reader may sway
  # it ('plus', 'sway') — a route may carry effects, chain into another pick (the bog
  # that takes three throws to escape), or simply be the end.
  def run_pick(book, pick, stats, items, luck = [])
    rolled = pick_number(book, pick, stats, items)
    route = pick['routes'].find { |r| rolled >= r.fetch('min', rolled) && rolled <= r.fetch('max', rolled) }
    luck << route['effects'] if route['effects']
    return [rolled, :death, luck] if route['die']
    return run_pick(book, route['pick'], stats, items, luck) if route['pick']

    [rolled, route['to'], luck]
  end

  def pick_number(book, pick, stats, items)
    rolled = Dice.roll(pick['roll'] || '1d10-1')
    rolled += pick_bonus(book, pick['plus'], items)
    Array(pick['sway']).each { |rule| rolled += rule['add'] if within?(rule, stats) }
    rolled
  end

  # What sweetens a throw: a named discipline or item held ('item'/'any'), or —
  # 'skilled' — fighting form, when the weapon in hand earns its Weaponskill bonus.
  def pick_bonus(book, plus, items)
    return 0 if plus.nil?
    return skilled_pick(book, plus, items) if plus['skilled']

    Array(plus['any'] || plus['item']).any? { |name| holds?(items, name) } ? plus['add'] : 0
  end

  def skilled_pick(book, plus, items)
    (armament(book, items) || [nil, 0]).last.positive? ? plus['add'] : 0
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
    notices = merge_notices(notices.dup, apply_effects(book, landing, stats, items))
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
    foe, = standing(from, fight)
    return redirect_to games_section_path(book: book['id'], section: params[:from]) if foe.nil?

    _, _, round, buff, mark = fight_parts(fight)
    mark = stats.fetch(loss_stat(book), 0) if fight.blank?
    number, foe_loss, hurt, remaining = strike_outcome(book, from, stats, items, fight)
    stats[loss_stat(book)] = [stats.fetch(loss_stat(book), 0) - hurt, 0].max

    index = from['combat']['enemies'].index(foe)
    fight = if remaining.positive?
              "#{index}:#{remaining}:#{round + 1}:#{buff}:#{mark}"
            else
              "#{index + 1}:next:#{round + 1}:#{buff}:#{mark}"
            end
    return if aftermath?(book, from, stats, items, fight, hurt: hurt)

    remember(book, params[:from], stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: params[:from],
                                   rn: number, foe: foe_loss, you: hurt)
  end

  # Everything a round can end besides the enemy: a contest settled, a wound the book
  # acts on, a victory judged by its speed, a fight the book cuts short.
  def aftermath?(book, from, stats, items, fight, hurt:)
    contest_settled?(book, from, stats, items, fight) ||
      on_wound?(book, from, stats, items, hurt) ||
      win_routed?(book, from, stats, items, fight) ||
      dragged_off?(book, from, stats, items, fight)
  end

  # The wound that ends the fight by itself — a Kalkoth's paralysing sting: any
  # endurance lost drags the living reader straight to the section the book names.
  def on_wound?(book, from, stats, items, hurt)
    to = from['combat']['on_wound']
    return false unless to && hurt.positive? && stats.fetch(loss_stat(book), 0).positive?

    travel(book, to, stats, items)
    true
  end

  # A victory the book judges by its speed: won inside the stated rounds it goes one
  # way, slower it goes the other.
  def win_routed?(book, from, stats, items, fight)
    rule = from['combat']['win_within']
    return false unless rule && standing(from, fight).nil? && stats.fetch(loss_stat(book), 0).positive?

    _, _, round, = fight_parts(fight)
    travel(book, round <= rule['rounds'] ? rule['to'] : rule['else'], stats, items)
    true
  end

  # One throw of the table, with everything the book lays on the wounds: the bane of
  # the undead — the Sommerswerd — doubles what such enemies lose, and a Mindforce
  # gnaws every round it is not shielded against, on top of the blade.
  def strike_outcome(book, from, stats, items, fight)
    combat = from['combat']
    _, remaining = standing(from, fight)
    number = rand(0..9)
    foe_loss, wolf_loss = LoneWolf.strike(combat_ratio(book, from, stats, items, fight), number)
    foe_loss *= 2 if combat['undead'] && foe_loss < LoneWolf::KILLED &&
                     battle_arms(book, combat, items).first == book['undead_bane']
    hurt = wolf_loss == LoneWolf::KILLED ? stats.fetch(loss_stat(book), 0) : wolf_loss
    hurt = temper(book, combat, stats, fight, hurt)
    [number, foe_loss, hurt + mindforce_toll(combat, items), foe_loss >= remaining ? 0 : remaining - foe_loss]
  end

  # What softens or sharpens a wound: the surprise that spares the first rounds
  # entirely, or fangs whose merest scratch is a throw between nothing and death.
  def temper(book, combat, stats, fight, hurt)
    _, _, round, = fight_parts(fight)
    return 0 if combat['shielded_rounds'] && round < combat['shielded_rounds']
    return hurt unless (fangs = combat['fangs']) && hurt.positive?

    rand(0..9) == fangs['die_on'] ? stats.fetch(loss_stat(book), 0) + hurt : 0
  end

  def mindforce_toll(combat, items)
    return 0 if combat['drain'].nil? || items.include?(combat.dig('drain', 'without'))

    combat.dig('drain', 'endurance').to_i
  end

  # A contest rather than a fight to the death — an arm-wrestle: the first to
  # nothing loses the match, not their life. Strength spent on the table comes back
  # when it ends, and the book names where each outcome leads.
  def contest_settled?(book, from, stats, items, fight)
    contest = from['combat']['contest']
    return false unless contest

    lost = stats.fetch(loss_stat(book), 0) <= 0
    return false unless lost || standing(from, fight).nil?

    stats[loss_stat(book)] = fight_parts(fight).last
    travel(book, lost ? contest['lose'] : contest['win'], stats, items)
    true
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
  # surprise that lasts one round, a battle draught's virtue, and the satchel's part.
  # A helper too: the combat panel prints it, so every modifier is visibly applied.
  def combat_ratio(book, from, stats, items, fight)
    combat = from['combat']
    foe, = standing(from, fight)
    _, _, round, buff = fight_parts(fight)

    ratio = stats.fetch('skill', 0) - foe['skill'] + buff + combat.fetch('modifier', 0)
    ratio += combat['surprise'].to_i if round.zero?
    ratio + kit_ratio(book, combat, items)
  end
  helper_method :combat_ratio

  # What the satchel adds: the weapon in hand, Mindblast unless this enemy shrugs it,
  # penalties without a named item (a torch in the dark, Mindshield against a
  # Mindforce), and anything — a Shield — the book says helps while carried.
  def kit_ratio(book, combat, items)
    # Books without a weapons table — the trial rigs — fight unarmed and unpenalised.
    bonus = (battle_arms(book, combat, items) || [nil, 0]).last
    if items.include?('mindblast') && !Array(combat['immune']).include?('mindblast')
      # A partially immune enemy states what the mind is worth against it.
      bonus += combat.fetch('mindblast', 2)
    end
    bonus + hindrances(combat, items) + trinkets(book, items)
  end

  def hindrances(combat, items)
    Array(combat['without']).sum { |rule| items.include?(rule['item']) ? 0 : rule['modifier'] }
  end

  def trinkets(book, items)
    (book['combat_items'] || {}).sum { |item, plus| items.include?(item) ? plus : 0 }
  end

  # What the fight is fought with, and what that is worth — for the ratio and for the
  # page to say. The reader never picks a weapon because there is nothing to pick:
  # a special weapon (the Sommerswerd) outranks everything, then the skilled weapon
  # counts whenever it is held. 'kin' names the weapon-like Special Items — a Magic
  # Spear is a spear to Weaponskill, but no thief or river takes it.
  def armament(book, items)
    rules = book['weapons']
    return nil if rules.nil?

    special = special_arm(rules, items)
    return special if special

    held = (rules['list'] + (rules['kin'] || {}).keys) & items
    return ['bare hands', rules.fetch('unarmed', -4)] if held.empty?

    match = held.find { |arm| skill_match?(rules, items, arm) }
    match ? [match, rules.fetch('bonus', 2)] : [held.first, 0]
  end
  helper_method :armament

  def special_arm(rules, items)
    (rules['special'] || {}).each do |name, art|
      next unless items.include?(name)

      skilled = Array(art['skilled']).include?(skilled_in(items))
      return [name, skilled ? art.fetch('skilled_bonus') : art.fetch('bonus')]
    end
    nil
  end

  def skill_match?(rules, items, arm)
    skilled = skilled_in(items)
    return false if skilled.nil?

    arm == skilled || (rules['kin'] || {})[arm] == skilled
  end

  # The fight's actual arms: the book may force them — 'bare hands' for a brawl the
  # blades cannot join, 'level' for a contest of strength, or a named weapon that is
  # the only thing that bites. Otherwise the armament speaks for itself.
  def battle_arms(book, combat, items)
    forced = combat['arms']
    return armament(book, items) if forced.nil?
    return ['bare hands', 0] if forced == 'level'

    forced_arm(book, forced, items)
  end
  helper_method :battle_arms

  def forced_arm(book, forced, items)
    return ['bare hands', book.dig('weapons', 'unarmed') || -4] if forced == 'bare hands' || !items.include?(forced)

    rules = book['weapons'] || {}
    [forced, skill_match?(rules, items, forced) ? rules.fetch('bonus', 2) : 0]
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
  # combat, any battle draught's bonus, and the health the fight was entered on (for
  # the contests that give it back). Older cookies carried fewer fields; the missing
  # ones read as zero.
  def fight_parts(fight)
    index, left, round, buff, mark = fight.to_s.split(':')
    [index.to_i, left, round.to_i, buff.to_i, mark.to_i]
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
    index, left, round, buff, mark = fight_parts(fight)
    if fight.blank?
      left = standing(book['sections'][section], fight).last
      mark = stats.fetch(loss_stat(book), 0)
    end
    fight = "#{index}:#{left}:#{round}:#{buff + provision['battle'].values.sum}:#{mark}"
    remember(book, section, stats, items, fight)
    redirect_to games_section_path(book: book['id'], section: section, used: params[:item])
  end

  def loss_stat(book)
    book['dies_at_zero'] || 'endurance'
  end

  # needs bars a choice without the named item; without bars it while the item is
  # held (the "if you do not possess" branch of a paper fork); when bars it by stat;
  # rank bars it below a count of disciplines (the Kai ranks are nothing more).
  def satisfied?(choice, stats, items)
    kit_allows?(choice, items) && within?(choice['when'], stats) &&
      (choice['cost'] || {}).all? { |stat, price| stats.fetch(stat, 0) >= price }
  end

  def kit_allows?(choice, items)
    return false if choice['needs'] && !holds?(items, choice['needs'])
    return false if choice['needs_any']&.none? { |name| holds?(items, name) }

    ranked?(choice, items) && unhindered?(choice, items)
  end

  def ranked?(choice, items)
    return false if choice['rank'] && rank_of(items) < choice['rank']

    choice['rank_below'].nil? || rank_of(items) < choice['rank_below']
  end

  def unhindered?(choice, items)
    return false if choice['without_any']&.any? { |name| holds?(items, name) }

    choice['without'].nil? || !holds?(items, choice['without'])
  end

  # Whether the satchel holds a thing, by any of the ways it can: as itself, as a
  # counted pile ("meal:3"), or — for Weaponskill — as the typed entry it rides as.
  def holds?(items, name)
    return items.any? { |held| held.start_with?('weaponskill in ') } if name == 'weaponskill'

    items.include?(name) || count_of(items, name).positive?
  end
  helper_method :holds?

  # The Kai rank, which is only the count of disciplines mastered: five to set out,
  # one more for each book survived.
  def rank_of(items)
    items.count do |held|
      DISCIPLINE_NAMES.include?(held) || held.start_with?('weaponskill in ')
    end
  end
  helper_method :rank_of

  DISCIPLINE_NAMES = ['camouflage', 'hunting', 'sixth sense', 'tracking', 'healing',
                      'weaponskill', 'mindshield', 'mindblast', 'animal kinship',
                      'mind over matter'].freeze

  def apply_effects(book, section, stats, items)
    effects = section && section['effects']
    return {} if effects.nil?

    apply_effect_hash(effects, book, stats, items)
  end

  # The keys that move things rather than numbers; everything else in an effects hash
  # is a stat and its delta — a plain number, or a dice string ('3d10', '-1d10') the
  # server throws on arrival.
  KIT_EFFECTS = %w[take drop gain steal drop_weapons drop_backpack drop_specials
                   must_eat risk unless boon recover].freeze

  def apply_effect_hash(effects, book, stats, items)
    notices = shift_kit(effects, book, items)
    upkeep(effects, book, stats, items, notices)

    # Every stat the page moves is reported as it actually landed — a pouch already
    # nearly full says +2, not the +15 the text promised — so nothing happens silently.
    changes = effects.except(*KIT_EFFECTS).filter_map do |stat, delta|
      before = stats.fetch(stat, 0)
      credit(stats, stat, measure(delta))
      landed = stats[stat] - before
      "#{stat}#{format('%+d', landed)}" unless landed.zero?
    end
    merge_notices(notices, { fx: changes.join(',') }) if changes.any?
    notices
  end

  def upkeep(effects, book, stats, items, notices)
    notices[:ate] = eat(book, stats, items, effects['must_eat']) if effects['must_eat']
    risk(effects['risk'], book, stats, items, notices) if effects['risk']
    spare(effects['unless'], book, stats, items, notices) if effects['unless']
    boon(effects['boon'], book, stats, items, notices) if effects['boon']
    recover(book, stats, items, effects['recover']) if effects['recover']
  end

  # A delta stated as dice is thrown here: '3d10' gold off a card table, '-1d10'
  # knocked into the Rymerift.
  def measure(delta)
    return delta unless delta.is_a?(String)

    delta.start_with?('-') ? -Dice.roll(delta[1..]) : Dice.roll(delta)
  end

  # An effect the named things ward off entirely — Mindshield against a one-off
  # Mindforce blast, Baknar oil against the cold — and its mirror: a boon that lands
  # only while one of them is held.
  def spare(rule, book, stats, items, notices)
    return if Array(rule['any'] || rule['item']).any? { |name| holds?(items, name) }

    merge_notices(notices, apply_effect_hash(rule['then'], book, stats, items))
  end

  def boon(rule, book, stats, items, notices)
    return unless Array(rule['any'] || rule['item']).any? { |name| holds?(items, name) }

    merge_notices(notices, apply_effect_hash(rule['then'], book, stats, items))
  end

  # A healer's ministrations: everything back with the named skill, half the losses
  # without it.
  def recover(book, stats, items, skill)
    stat = loss_stat(book)
    ceiling = stats.fetch("#{stat}_max", stats.fetch(stat, 0))
    lost = ceiling - stats.fetch(stat, 0)
    credit(stats, stat, items.include?(skill) ? lost : lost / 2)
  end

  # Notices folded together without losing news: the fx ledgers concatenate where
  # every other key simply takes the later value.
  def merge_notices(base, extra)
    fx = [base[:fx], extra[:fx]].compact_blank.join(',')
    base.merge!(extra)
    base[:fx] = fx if fx.present?
    base
  end

  # The satchel side of an effects hash: things taken, dropped, gained by the
  # handful, stolen, or lost wholesale — each reported, so nothing happens silently.
  def shift_kit(effects, book, items)
    notices = swap_kit(effects, items)
    notices[:lost] = steal(book, items) if effects['steal']
    shed_weapons(book, items, effects['drop_weapons'], notices) if effects['drop_weapons']
    strip_backpack(book, items) if effects['drop_backpack']
    items.reject! { |held| Array(book['worn']).include?(held) } if effects['drop_specials']
    notices
  end

  def swap_kit(effects, items)
    notices = {}
    got = Array(effects['take']).filter_map { |item| take_item(item, items) }
    notices[:got] = got.join(' and the ') if got.any?
    Array(effects['drop']).each { |gone| items.delete(gone) }
    gains = (effects['gain'] || {}).map do |name, extra|
      add_count(items, name, extra)
      "#{name}#{format('%+d', extra)}"
    end
    notices[:fx] = gains.join(',') if gains.any?
    notices.compact
  end

  def take_item(item, items)
    return nil if item.nil? || items.include?(item)

    items << item
    item
  end

  # All the weapons; 'one' breaks the plainest of them — the skilled arm is spared,
  # as any reader given the choice would spare it; 'wielded' takes the one in hand.
  def shed_weapons(book, items, rule, notices)
    return items.reject! { |held| weapons_list(book).include?(held) } if rule == true

    held = items & weapons_list(book)
    return if held.empty?

    broken = breakable(book, items, held, rule)
    items.delete(broken)
    notices[:lost] = broken
  end

  def breakable(book, items, held, rule)
    if rule == 'wielded'
      arm = (armament(book, items) || []).first
      held.include?(arm) ? arm : held.first
    else
      (held - [skilled_in(items)]).first || held.first
    end
  end

  # The weapon Weaponskill was learned in, off the satchel's own entry.
  def skilled_in(items)
    items.filter_map { |entry| entry[/\Aweaponskill in (.+)\z/, 1] }.first
  end

  # A throw of the Random Number Table inside an effects hash: the bolt that may or
  # may not hit. One branch of effects lands, by the roll.
  def risk(rule, book, stats, items, notices)
    rolled = Dice.roll(rule['roll'] || '1d10-1')
    hit = rolled >= rule.fetch('at_least', rolled) && rolled <= rule.fetch('at_most', rolled)
    branch = hit ? rule['then'] : rule['else']
    merge_notices(notices, apply_effect_hash(branch, book, stats, items)) if branch
  end

  # The book has said "you must now eat": Hunting feeds the hunter for nothing
  # (unless this stretch of country has nothing to hunt), a Meal is eaten from the
  # satchel, Laumspur serves as one (and heals as it always does), and an empty
  # satchel costs the hungry what the rules say — three points, or the rule's own.
  def eat(book, stats, items, rule)
    rule = {} unless rule.is_a?(Hash)
    return sit_down_meal(book, stats, items, rule) if rule['meals']
    return 'hunting' if items.include?('hunting') && rule['hunting'] != false
    return 'meal' if spend(items, 'meal')

    eat_laumspur(book, stats, items, rule)
  end

  def eat_laumspur(book, stats, items, rule)
    return famine(book, stats, rule) unless spend(items, 'laumspur')

    laumspur_virtue(book).each { |stat, delta| credit(stats, stat, delta) }
    'laumspur'
  end

  # The page that demands more than one meal at a sitting.
  def sit_down_meal(book, stats, items, rule)
    Array.new(rule['meals']) { eat(book, stats, items, rule.except('meals')) }.last
  end

  def laumspur_virtue(book)
    book.dig('consumables', 'laumspur', 'effects') || {}
  end

  def famine(book, stats, rule)
    stats[loss_stat(book)] = [stats.fetch(loss_stat(book), 0) - rule.fetch('penalty', 3), 0].max
    'nothing'
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
    items << "#{name}:#{total}" if total.positive?
  end

  # Taking an offer up: the price is paid, a chit is spent, any stated boon lands
  # (a waistcoat's endurance, ceiling and all); counted things join their pile; a
  # weapon may cost the belt its plainest arm — the one Weaponskill was not learned
  # in — either because the offer is an exchange or because two are already carried.
  # An offer may bring companions ('with'), for the pages that hand over a find in
  # one go.
  def claim(book, offer, stats, items)
    levy(book, offer, stats, items)
    return add_count(items, offer['item'], offer['count']) && nil if offer['count']

    gave = make_room(book, offer, items)
    items << offer['item']
    Array(offer['with']).each do |extra|
      next if items.include?(extra)

      gave ||= make_room(book, { 'item' => extra }, items)
      items << extra
    end
    gave
  end

  # The taking's price: gold, a chit, and any stated boon applied.
  def levy(book, offer, stats, items)
    stats['gold'] = stats.fetch('gold', 0) - offer['price'] if offer['price']
    spend(items, offer['spends']) if offer['spends']
    (offer['effects'] || {}).each { |stat, delta| boost(book, stats, stat, delta) }
  end

  def make_room(book, offer, items)
    held = items & weapons_list(book)
    return nil unless weapons_list(book).include?(offer['item'])
    return nil if held.empty? || (held.length < 2 && !offer['swap'])

    discard = (held - [skilled_in(items)]).first || held.first
    items.delete(discard)
    discard
  end

  # The character as it stands — or, when the book holds none yet, carried over from
  # the book this one continues, or rolled fresh from the book's own dice: stats with
  # their maximums and caps, disciplines drawn, Weaponskill given its weapon, and the
  # starting equipment table thrown.
  def character(book)
    return [{}, []] if book['stats'].nil?

    stats, items = unpack(bookmarks[book['id']])
    return [stats, items] if stats.present?

    inherit(book) || roll_fresh(book)
  end

  def roll_fresh(book)
    rolled = book['stats'].transform_values { |stat| Dice.roll(stat['start'].to_s) }
    book['stats'].each do |name, stat|
      rolled["#{name}_max"] = rolled[name] if stat['max']
      rolled["#{name}_max"] = stat['cap'] if stat['cap']
    end
    items = outfit(book)
    endow(book, rolled, items)
    [rolled, items]
  end

  # The Kai Lord who finished the previous book walks straight into this one, as the
  # series rules allow: stats, disciplines, weapons, satchel and gold all carried,
  # one further discipline learned on the road, and a fresh purse thrown and added.
  # Only a bookmark standing on the named final page counts as finished.
  def inherit(book)
    legacies = book['sequel_of'].is_a?(Hash) ? [book['sequel_of']] : Array(book['sequel_of'])
    legacies.each do |legacy|
      stats, items = finished_legacy(book, legacy)
      next if stats.nil?

      stats['gold_max'] = book.dig('stats', 'gold', 'cap') if book.dig('stats', 'gold', 'cap')
      credit(stats, 'gold', Dice.roll(legacy['purse'] || '1d10+9')) if legacy['purse']
      return [stats, items + [new_discipline(book, items)].compact + Array(book['items'])]
    end
    nil
  end

  # The previous book's character, if its bookmark stands on the named final page
  # with life left in them.
  def finished_legacy(book, legacy)
    section, = bookmarks[legacy['book']].to_s.split('|')
    stats, items, = unpack(bookmarks[legacy['book']])
    return nil unless section == legacy['at'] && stats.present? &&
                      stats.fetch(loss_stat(book), 0).positive?

    [stats.dup, items]
  end

  def new_discipline(book, items)
    pool = book['item_draw']['from'].reject do |discipline|
      items.include?(discipline) ||
        (discipline == 'weaponskill' && items.any? { |held| held.start_with?('weaponskill in ') })
    end
    drawn = pool.sample
    return drawn unless drawn == 'weaponskill' && (table = book.dig('weapons', 'skill_table'))

    "weaponskill in #{table.sample}"
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
