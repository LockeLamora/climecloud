# frozen_string_literal: true

require 'zlib'

# The Long Haul: 2,400 AU of dead space with a sealed cryo-pod in the hold, payment on
# delivery at Samarkand Station, and standing instructions not to ask. The lanes are
# fixed the moment the run begins: every day's trouble comes from a checksum of the
# run's seed and the day, so a reload shows the same void. Every note says what it did
# in numbers. Stations are the only places that sell anything or pay for work — between
# them there is nothing but what the drift gives up.
class JourneyController < ApplicationController
  DISTANCE = 2400
  CREW = %w[Vex Moth Saint].freeze

  # The docks along the lane. A burn that would pass one stops there instead: fuel,
  # rations, parts and paying work exist only where there is a dock to hold them.
  STATIONS = [
    [0, 'Erebus Dock', ''],
    [400, 'the Salt Havens', 'The Salt Havens: brine-farmers and bootleg oxygen, and half the dock lights dead.'],
    [1000, 'Tabernacle Station',
     'Tabernacle Station: the Choir runs it — hymns on every channel, a knife under every cassock.'],
    [1700, 'the Gate of Grins',
     'The Gate of Grins: a ring of figureheads cut from dead ships. Nobody remembers who started it.'],
    [2200, 'Threadneedle', 'Threadneedle: the last dock before the deep dark, and prices that know it.'],
    [2400, 'Samarkand Station', '']
  ].freeze

  # The lane's toll-keepers: each stops the ship until an answer is given — pay the
  # safe way through, chance the cheap way, or hold a day and let the luck change.
  CROSSINGS = [
    { at: 700, name: 'The Customs Chain', pay: 'Pay the "inspection fee"', fare: 30,
      risk: 'Run the chain dark',
      mishap: [:petrol, -8, 'A tether-mine clipped the drive shielding: fuel -8.'],
      across: 'Threaded the chain between sweeps, running silent.' },
    { at: 1350, name: 'The Reef of Wrecks', pay: 'Hire a wreck-pilot through', fare: 25,
      risk: 'Thread the reef on instruments',
      mishap: [:health, -2, 'A hull-shard breached deck two: crew -2.'],
      across: 'Through the reef with paint to spare.' },
    { at: 1950, name: 'The Tithe-Ships of the Choir', pay: 'Pay the tithe', fare: 35,
      risk: 'Refuse the blessing and burn past',
      mishap: [:food, -6, 'Their boarding-hymn party got into the stores: rations -6.'],
      across: 'The Choir found nothing aboard worth taking. They seemed disappointed.' }
  ].freeze

  # Nothing between the docks is worth a line every day, but some days the void is.
  SCENERY = [
    'The pod in the hold hums a fifth below the drive note. Nobody mentions it.',
    'A cult beacon recites names for six hours straight. None are yours. Probably.',
    'Something big passed within a light-second, running dark. It did not hail.',
    'Moth swears the airlock cycled itself in the night. The log agrees with Moth.',
    'An empty suit tethered to a marker buoy, waving with the current.',
    'A liner-sized shadow on the long scan for one sweep, then nothing. Saint logs it as weather.',
    "Somebody has scratched tallies inside the pod bay door. They are not the crew's."
  ].freeze

  # A mercenary cutter matching velocity: the one trouble that waits for an answer.
  BANDITS = 4

  MOVES = {
    'steady' => { miles: 80, petrol: -4, food: -2, health: 0 },
    'push' => { miles: 130, petrol: -7, food: -3, health: -1 },
    'rest' => { miles: 0, petrol: 0, food: -2, health: 2 }
  }.freeze
  WARES = { 'buy_petrol' => [30, :petrol, 10, 'Fuel'], 'buy_food' => [20, :food, 10, 'Rations'],
            'buy_spare' => [50, :spares, 1, 'A drive part'] }.freeze

  def show
    @run = state
    @arrived = @run[:miles] >= DISTANCE
    @perished = @run[:health] <= 0
    @ambushed = @run[:pending] == BANDITS
    @crossing = CROSSINGS[@run[:pending] - 1] if @run[:pending].between?(1, CROSSINGS.length)
    @docked = STATIONS.find { |at, _| at == @run[:miles] }
    @behind, @ahead = neighbours(@run[:miles])
  end

  def act
    run = state
    if run[:pending] == BANDITS
      ambush_move(run)
    elsif run[:pending].positive?
      crossing_move(run)
    else
      space_move(run)
    end
    redirect_to games_journey_path
  end

  def restart
    cookies.delete('JOURNEY')
    redirect_to games_journey_path
  end

  private

  def space_move(run)
    if (move = MOVES[params[:move]])
      burn(run, move)
    else
      errand(run, STATIONS.any? { |at, _| at == run[:miles] })
    end
  end

  # The day's business off the throttle: shifts and shopping belong to the docks, the
  # trawl to the deep dark, and asking in the wrong place is refused out loud.
  def errand(run, docked)
    case params[:move]
    when 'work'
      return refuse(run, 'No dock, no shift: work waits at the next station.') unless docked

      pass_day(run, cash: 25, note: 'A shift unloading ore at the dock: scrip +25.')
    when 'trawl'
      return refuse(run, 'The dockmaster frowns on trawling his lanes: cast off first.') if docked

      trawl(run)
    else
      ware = WARES[params[:move]]
      return if ware.nil?
      return refuse(run, 'Nothing to buy out here but vacuum: the shops are at the stations.') unless docked

      barter(run, ware)
    end
  end

  def burn(run, move)
    if run[:petrol] + move[:petrol] >= 0
      travel(run, move)
    else
      refuse(run, "The ship stays put: that burn needs #{-move[:petrol]} fuel " \
                  "and the tank holds #{run[:petrol]}.")
    end
  end

  # A day dredging the drift: the void pays in rations, fuel, a story — or trouble.
  # Half the days pay nothing or worse, so the trawl is a gamble to lean on, never a
  # larder to live from.
  def trawl(run)
    haul = roll(run, 'trawl')
    case haul % 10
    when 0..2
      found = 3 + (haul % 4)
      pass_day(run, food: found, note: "The trawl nets a ration crate off a dead hulk: rations +#{found}.")
    when 3..4
      run[:petrol] += 2 + (haul % 3)
      pass_day(run, note: "A wreck with sealed tanks: fuel +#{2 + (haul % 3)}.")
    when 5..6
      pass_day(run, note: 'A day trawling for nothing but grave-goods and static.')
    when 7
      run[:health] = [run[:health] - 1, 0].max
      pass_day(run, note: 'The trawl comes back with a contact mine, half-live. Cutting it loose costs: crew -1.')
    when 8
      pass_day(run, food: -2,
                    note: 'The trawl drags in crates gone badly wrong. Two of ours spoil in sympathy: rations -2.')
    else
      run[:pending] = BANDITS
      pass_day(run, note: "Something answered the trawl's ping. A drive flare on the scan, turning this way.")
    end
  end

  # What did not happen, and why — written where the reader will see it rather than
  # swallowed. The mark in front picks the red ink in the view; the day does not turn.
  def refuse(run, why)
    save(run.merge(note: "!#{why}"))
  end

  def barter(run, ware)
    cost, item, amount, name = ware
    if run[:cash] >= cost
      run[item] += amount
      run[:cash] -= cost
      save(run.merge(note: "#{name} bought: scrip -#{cost}."))
    else
      refuse(run, "#{name} costs #{cost} and the purse holds #{run[:cash]}: nothing bought.")
    end
  end

  def travel(run, move)
    run[:petrol] += move[:petrol]
    run[:health] = [run[:health] + move[:health], 10].min
    target = run[:miles] + move[:miles]

    halt = barrier(run[:miles], target)
    return halt_at(run, halt, move) if halt

    dock = berth(run[:miles], target)
    return dock_at(run, dock, move) if dock

    run[:miles] = target
    pass_day(run, food: move[:food], note: move[:miles].positive? ? befall(run) : '')
  end

  def barrier(from, target)
    CROSSINGS.find { |crossing| from < crossing[:at] && target >= crossing[:at] }
  end

  def berth(from, target)
    STATIONS.find { |at, _, _| from < at && target >= at && at < DISTANCE }
  end

  def halt_at(run, halt, move)
    run[:miles] = halt[:at]
    run[:pending] = CROSSINGS.index(halt) + 1
    pass_day(run, food: move[:food], note: "The lane is barred: #{halt[:name].downcase}.")
  end

  # A burn that would pass a dock stops there instead: the only shops and the only
  # work on the lane are behind those berths.
  def dock_at(run, dock, move)
    run[:miles] = dock[0]
    pass_day(run, food: move[:food], note: dock[2].presence || "Docked at #{dock[1]}.")
  end

  def crossing_move(run)
    crossing = CROSSINGS[run[:pending] - 1]
    case params[:move]
    when 'pay'
      if run[:cash] < crossing[:fare]
        return refuse(run, "They want #{crossing[:fare]} and the purse holds #{run[:cash]}.")
      end

      run[:cash] -= crossing[:fare]
      run[:pending] = 0
      pass_day(run, food: -1, note: "#{crossing[:across]} (scrip -#{crossing[:fare]}, rations -1.)")
    when 'risk'
      stat, cost, tale = crossing[:mishap]
      run[:pending] = 0
      if (roll(run, 'crossing') % 100) < 45
        run[stat] = [run[stat] + cost, 0].max
        pass_day(run, food: -1, note: "#{tale} Through all the same. (rations -1.)")
      else
        pass_day(run, food: -1, note: "#{crossing[:across]} (rations -1.)")
      end
    when 'wait'
      pass_day(run, food: -2,
                    note: 'A day holding position off the barrier: rations -2. The watch changes with the day.')
    end
  end

  def ambush_move(run)
    case params[:move]
    when 'pay_off'
      return refuse(run, "They want 20 and the purse holds #{run[:cash]}.") if run[:cash] < 20

      run[:cash] -= 20
      run[:pending] = 0
      save(run.merge(note: 'Twenty in hard scrip through the tether-line, and the cutter casts off: scrip -20.'))
    when 'run_for_it'
      return refuse(run, "Outrunning a cutter needs 6 fuel and the tank holds #{run[:petrol]}.") if run[:petrol] < 6

      flee(run)
    when 'fight'
      fight(run)
    end
  end

  def flee(run)
    run[:petrol] -= 6
    run[:pending] = 0
    if (roll(run, 'chase') % 100) < 40
      run[:petrol] = [run[:petrol] - 5, 0].max
      save(run.merge(note: 'Outrun, but a rail-slug holed a tank: fuel -6 for the burn, -5 more vented.'))
    else
      save(run.merge(note: 'The old girl shows the cutter a clean wake: fuel -6.'))
    end
  end

  def fight(run)
    run[:pending] = 0
    if (roll(run, 'fight') % 100) < 50
      run[:cash] += 25
      save(run.merge(note: 'The boarders meet Vex at the inner hatch and think better ' \
                           'of it. Their kit stays behind: scrip +25.'))
    else
      run[:health] = [run[:health] - 3, 0].max
      save(run.merge(note: 'A fight through the ring corridor. They withdraw, but it cost: crew -3.'))
    end
  end

  # Every day ends here: the ledger applied, hunger enforced — an empty galley costs
  # the crew until it is filled — and the day turned over.
  def pass_day(run, food: 0, cash: 0, note: '')
    run[:day] += 1
    run[:cash] += cash
    run[:food] += food
    if run[:food] <= 0
      run[:food] = 0
      run[:health] -= 2
      note = "#{note} The galley is empty: crew -2.".strip
    end
    save(run.merge(note: note))
  end

  # What the void had waiting that day, told with its numbers. The worst of it — a
  # cutter on an intercept line — is the rarest, and stops the ship for an answer.
  def befall(run)
    toll = roll(run, 'road') % 100
    return '' if toll < 25
    return SCENERY[roll(run, 'scenery') % SCENERY.length] if toll < 35
    return breakdown(run) if toll < 45
    return fortune(run, toll) if toll < 78
    return misfortune(run, toll) if toll < 96

    run[:pending] = BANDITS
    'A mercenary cutter matches velocity, grapnels out. They have seen the pod\'s manifest.'
  end

  def fortune(run, toll)
    case toll
    when 45..51
      run[:food] = [run[:food] - 4, 0].max
      'A recycler fault soured the tanks: rations -4.'
    when 52..58
      run[:food] += 6
      'A vagabond barge trades ration bricks for news of the inner lanes: rations +6.'
    when 59..65
      run[:petrol] += 6
      'A drifting hulk with sealed reserve tanks: fuel +6.'
    when 66..71
      run[:cash] += 30
      'A frightened passenger pays for a berth to the next dock and asks no questions either: scrip +30.'
    else
      run[:spares] += 1
      'A stripped freighter, but the scavengers missed a coil in the keel: parts +1.'
    end
  end

  def misfortune(run, toll)
    case toll
    when 78..82
      if run[:cash] >= 10
        run[:cash] -= 10
        'A Choir tithe-drone latches to the hull and chants until paid: scrip -10.'
      else
        run[:food] = [run[:food] - 3, 0].max
        'A Choir tithe-drone latches on; with no scrip aboard it takes its due in kind: rations -3.'
      end
    when 83..87
      run[:health] = [run[:health] - 2, 0].max
      "#{CREW[roll(run, 'fever') % CREW.length]} took a rad-burn at the collectors: crew -2."
    when 88..91
      run[:miles] = [run[:miles] - 30, 0].max
      'Saint swears the charts moved in the night. 30 AU retraced before anyone believed the stars.'
    else
      run[:miles] = [run[:miles] - 40, 0].max
      run[:health] = [run[:health] - 1, 0].max
      'A particle squall: 40 AU lost running shielded, crew -1.'
    end
  end

  def breakdown(run)
    if run[:spares].positive?
      run[:spares] -= 1
      'A drive coil blew: parts -1.'
    else
      run[:miles] -= 60
      run[:food] = [run[:food] - 3, 0].max
      'A drive coil blew with no part to fit: 60 AU lost limping, rations -3.'
    end
  end

  def roll(run, purpose)
    Zlib.crc32("#{run[:seed]}:#{run[:day]}:#{purpose}")
  end

  def neighbours(miles)
    marks = (STATIONS.map { |at, name, _| [at, name] } +
             CROSSINGS.map { |crossing| [crossing[:at], crossing[:name].downcase] }).sort_by(&:first)
    [marks.select { |at, _| at <= miles }.last, marks.find { |at, _| at > miles }]
  end

  FIELDS = %i[seed day miles petrol food spares health cash pending].freeze

  def save(run)
    cookies.permanent['JOURNEY'] = (FIELDS.map { |field| run[field] } + [run[:note]]).join('|')
  end

  def state
    parts = cookies['JOURNEY'].to_s.split('|')
    parts = [rand(10_000), 1, 0, 40, 30, 2, 10, 120, 0, ''].map(&:to_s) unless parts.length >= 9
    run = FIELDS.each_with_index.to_h { |field, index| [field, parts[index].to_i] }
    run[:note] = parts[9].to_s
    run
  end
end
