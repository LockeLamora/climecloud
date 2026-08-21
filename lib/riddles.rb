# frozen_string_literal: true

# One riddle a day, drawn from the anonymous folk riddles the Victorians collected —
# all of them centuries old and long in the public domain. Three answers offered; the
# right one sits where the author put it.
module Riddles
  LIST = [
    { q: 'As I was going to St Ives, I met a man with seven wives. Each wife had ' \
         'seven sacks, each sack had seven cats, each cat had seven kits. Kits, ' \
         'cats, sacks and wives, how many were going to St Ives?',
      a: ['Two thousand eight hundred', 'One', 'Forty-nine'], right: 1 },
    { q: 'In marble halls as white as milk, lined with a skin as soft as silk, ' \
         'within a fountain crystal clear, a golden apple doth appear. No doors ' \
         'there are to this stronghold, yet thieves break in and steal the gold.',
      a: ['An egg', 'A beehive', 'A church'], right: 0 },
    { q: 'Thirty white horses upon a red hill: now they tramp, now they champ, now ' \
         'they stand still.',
      a: ['Waves on the shore', 'Soldiers drilling', 'Teeth'], right: 2 },
    { q: 'Little Nancy Etticoat, in a white petticoat and a red nose: the longer ' \
         'she stands, the shorter she grows.',
      a: ['A candle', 'An icicle', 'A carrot'], right: 0 },
    { q: 'Old Mother Twitchett had but one eye, and a long tail which she let fly; ' \
         'and every time she went over a gap, she left a bit of her tail in a trap.',
      a: ['A comet', 'A needle and thread', 'A mouse'], right: 1 },
    { q: 'Runs all day and never walks; often murmurs, never talks; has a bed but ' \
         'never sleeps; has a mouth but never eats.',
      a: ['A river', 'A clock', 'The wind'], right: 0 },
    { q: 'The more you take of me, the more you leave behind. What am I?',
      a: %w[Time Money Footsteps], right: 2 },
    { q: 'Feed me and I live; give me a drink and I die. What am I?',
      a: ['Fire', 'A fish', 'Thirst'], right: 0 },
    { q: 'What has a neck, but no head?',
      a: ['A shirt', 'A bottle', 'A river'], right: 1 },
    { q: 'Forward I am heavy, but backward I am not. What am I?',
      a: ['An anchor', 'A shadow', 'A ton'], right: 2 },
    { q: 'What is full of holes and still holds water?',
      a: ['A sponge', 'A sieve', 'A net'], right: 0 },
    { q: 'White bird featherless flew from Paradise, pitched on the castle wall; ' \
         'along came Lord Landless, took it up handless, and rode away horseless ' \
         'to the King\'s white hall.',
      a: ['A ghost', 'Snow and the sun', 'A letter'], right: 1 },
    { q: 'Elizabeth, Elspeth, Betsy and Bess, they all went together to seek a ' \
         'bird\'s nest. They found a bird\'s nest with five eggs in; they all took ' \
         'one, and left four in.',
      a: ['They were all one person', 'The eggs were doubled', 'One was empty-handed'],
      right: 0 },
    { q: 'As round as an apple, as deep as a cup, and all the king\'s horses ' \
         'cannot fill it up.',
      a: ['The sea', 'A well', 'A church bell'], right: 1 },
    { q: 'Long legs, crooked thighs, little head and no eyes.',
      a: ['A pair of tongs', 'A spider', 'A wishbone'], right: 0 },
    { q: 'Flour of England, fruit of Spain, met together in a shower of rain; put ' \
         'in a bag tied round with a string; if you\'ll tell me this riddle, I\'ll ' \
         'give you a ring.',
      a: ['A wedding cake', 'A plum pudding', 'A market stall'], right: 1 },
    { q: 'Lives in winter, dies in summer, and grows with its root upward.',
      a: ['An icicle', 'A fir tree', 'A snowdrop'], right: 0 },
    { q: 'What does God never see, what does the king seldom see, and what do we ' \
         'see every day?',
      a: ['The dark', 'A dream', 'An equal'], right: 2 },
    { q: 'I went to the wood and got it; I sat me down and sought it; I kept it ' \
         'still against my will, and so by force home brought it.',
      a: ['A thorn in the foot', 'A stubborn donkey', 'A cold'], right: 0 },
    { q: 'The land was white, the seed was black; it will take a good scholar to ' \
         'riddle me that.',
      a: ['A snowy field of crows', 'Paper and writing', 'The night sky'], right: 1 },
    { q: 'What goes up and never comes down?',
      a: ['Your age', 'Smoke', 'A prayer'], right: 0 },
    { q: 'Brothers and sisters have I none, but that man\'s father is my ' \
         'father\'s son. Who is that man?',
      a: ['My father', 'My son', 'Myself'], right: 1 },
    { q: 'What has an eye, but cannot see?',
      a: ['A potato', 'A storm', 'A needle'], right: 2 },
    { q: 'What gets wetter the more it dries?',
      a: ['A towel', 'A river bed', 'The morning dew'], right: 0 }
  ].freeze

  # The day picks the riddle, the same one for everybody until midnight.
  def self.today(date)
    LIST[date.jd % LIST.length]
  end
end
