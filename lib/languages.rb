# frozen_string_literal: true

class Languages
  SUPPORTED = %w[en hi bn id ur ar sw ru tr vi fr de es it nl pt pl].freeze

  # Written right to left, so the page direction has to flip with them.
  RIGHT_TO_LEFT = %w[ar ur].freeze

  # Weighted towards where feature phones are actually the main phone rather than a
  # minimalist choice: India, Bangladesh, Pakistan, Indonesia, east and west Africa,
  # and the Arabic speaking world.
  #
  # English first, always. Someone carrying a dumbphone abroad may not read the local
  # language, so it stays the one option that is never wrong to offer.
  BY_COUNTRY = {
    'ae' => %w[ar], 'ar' => %w[es], 'at' => %w[de], 'bd' => %w[bn],
    'be' => %w[nl fr], 'br' => %w[pt], 'ca' => %w[fr], 'ch' => %w[de fr it],
    'cl' => %w[es], 'co' => %w[es], 'de' => %w[de], 'dz' => %w[ar fr],
    'eg' => %w[ar], 'es' => %w[es], 'fr' => %w[fr], 'id' => %w[id],
    'in' => %w[hi bn], 'iq' => %w[ar], 'it' => %w[it], 'jo' => %w[ar],
    'ke' => %w[sw], 'kw' => %w[ar], 'lu' => %w[fr de], 'ma' => %w[ar fr],
    'mx' => %w[es], 'ng' => %w[en], 'nl' => %w[nl], 'np' => %w[hi],
    'pe' => %w[es], 'pk' => %w[ur], 'pl' => %w[pl], 'pt' => %w[pt],
    'ru' => %w[ru], 'sa' => %w[ar], 'sd' => %w[ar], 'tn' => %w[ar fr],
    'tr' => %w[tr], 'tz' => %w[sw], 'ua' => %w[ru], 'ug' => %w[sw],
    'uy' => %w[es], 've' => %w[es], 'vn' => %w[vi], 'ye' => %w[ar]
  }.freeze

  def self.for_country(country_code)
    spoken = BY_COUNTRY[country_code.to_s.downcase] || []

    (['en'] + spoken).uniq & SUPPORTED
  end

  # Always include whatever the reader is currently using, or moving to a country
  # that speaks only one language would hide the picker and strand them in a
  # language they cannot read their way out of.
  def self.offered_for(country_code, current_locale)
    (for_country(country_code) + [current_locale.to_s]).uniq & SUPPORTED
  end

  def self.supported?(locale)
    SUPPORTED.include?(locale.to_s)
  end

  def self.name_for(locale)
    I18n.t('language_name', locale: locale)
  end

  def self.direction_for(locale)
    RIGHT_TO_LEFT.include?(locale.to_s) ? 'rtl' : 'ltr'
  end
end
