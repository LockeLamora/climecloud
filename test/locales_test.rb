# frozen_string_literal: true

require 'test_helper'

# Locale files agreeing with each other is not enough: they have to satisfy the keys
# the code actually asks for. A missing translation reached production because every
# locale carried "field_from" while the code requested "field_origin".
class LocalesTest < ActiveSupport::TestCase
  # Keys built at runtime cannot be found by reading the source for literals, so they
  # are enumerated from the constants that drive them.
  def dynamic_keys
    modes = (Departures::MODE_KEYS.values + Departures::EXTENDED_MODES.values).uniq

    %w[language_name places.kind.unnamed] +
      %w[origin destination].map { |field| "directions.field_#{field}" } +
      Places::CATEGORIES.keys.map { |kind| "places.category.#{kind}" } +
      Places::KIND_KEYS.values.map { |kind| "places.kind.#{kind}" } +
      Maps::COMPASS_POINTS.map { |point| "compass.#{point}" } +
      modes.map { |mode| "departures.mode.#{mode}" } +
      (Maps::STATUS_KEYS.values + ['could_not_plan']).map { |key| "directions.#{key}" }
  end

  # Anything written as t('some.key') or I18n.t('some.key'). The lookbehind keeps it
  # from matching the tail of method names such as split( or get_forecast(.
  def literal_keys
    Dir[Rails.root.join('app/**/*.{rb,erb}'), Rails.root.join('lib/**/*.rb')].flat_map do |file|
      File.read(file).scan(/(?<![A-Za-z0-9_.])(?:I18n\.)?t\(\s*['"]([a-z0-9_.]+)['"]/).flatten
    end
  end

  def required_keys
    (literal_keys + dynamic_keys).uniq.sort
  end

  def flatten(hash, prefix = '')
    hash.flat_map do |key, value|
      value.is_a?(Hash) ? flatten(value, "#{prefix}#{key}.") : ["#{prefix}#{key}"]
    end
  end

  # A pluralised entry is satisfied by its one/other children rather than itself.
  def satisfied?(key, present)
    present.include?(key) || present.any? { |candidate| candidate.start_with?("#{key}.") }
  end

  test 'every locale has a translation for every key the code asks for' do
    keys = required_keys
    assert_operator keys.length, :>, 100, 'key extraction found suspiciously few keys'

    Languages::SUPPORTED.each do |locale|
      present = flatten(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale])
      missing = keys.reject { |key| satisfied?(key, present) }

      assert_empty missing, "#{locale} is missing: #{missing.join(', ')}"
    end
  end

  test 'no locale carries keys the code never asks for' do
    keys = required_keys

    Languages::SUPPORTED.each do |locale|
      present = flatten(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale])
      unused = present.reject do |key|
        keys.include?(key) || keys.any? { |required| key.start_with?("#{required}.") }
      end

      assert_empty unused, "#{locale} carries unused keys: #{unused.join(', ')}"
    end
  end

  test 'every locale is offered a readable name in its own language' do
    Languages::SUPPORTED.each do |locale|
      assert_not_equal '', Languages.name_for(locale).to_s.strip, "#{locale} has no language_name"
    end
  end
end
