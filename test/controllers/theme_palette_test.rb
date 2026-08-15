# frozen_string_literal: true

require 'test_helper'

# The palette is written into every page's head as ordinary declarations, because Opera
# Mini 4.4 on the target handset discards any declaration whose value is a var() call and
# would otherwise render every theme as the plain default.
#
# These tests hold that contract at the markup level. The colours a browser resolves from
# the markup are ThemeTest's subject.
class ThemePaletteTest < ActionDispatch::IntegrationTest
  # Every colour a component paints with at rest. press.css is not among them: it styles a
  # press, reads the palette through tokens, and a browser that ignores those keeps the
  # resting colours underneath.
  CONSUMED = %i[paper ink link quiet rule head_bg head_ink error].freeze

  test 'every theme reaches the page as declarations a browser without var() can read' do
    Themes::NAMES.each do |name|
      get settings_url, headers: { 'HTTP_COOKIE' => "theme=#{name}" }

      assert_response :success

      palette = Themes.palette(name)
      literals = declarations(style_block).grep_v(/\A--/)

      CONSUMED.each do |token|
        assert literals.any? { |d| d.end_with?(palette[token]) },
               "#{name}: #{token} is #{palette[token]}, which no literal declaration carries"
      end

      assert_empty literals.grep(/var\(/),
                   "#{name}: the palette reaches the handset only as literal values"
    end
  end

  # The two properties that decide whether a theme is recognisable at all, checked against
  # the body rule rather than against the block as a whole.
  test 'the paper and the ink are resolved on the body itself' do
    palette = Themes.palette('crt-amber')

    get settings_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber' }

    assert_match(/body\{[^}]*;background:#{palette[:paper]};color:#{palette[:ink]}\}/, style_block)
  end

  test 'every offered theme states a full palette' do
    Themes::NAMES.each do |name|
      palette = Themes.palette(name)

      assert_empty Themes::BASE_PALETTE.keys - palette.keys, "#{name} is missing a colour"
      assert_empty palette.select { |_, value| value.blank? }, "#{name} leaves a colour blank"
    end
  end

  # A style whose brightness is shared between its ink and a text-shadow has to hand the
  # handset a colour that stands on its own, since no shadow will be drawn behind it. The
  # dimmer value goes out only inside @supports, which the handset skips whole.
  test 'a style with a glow gives the brighter ink to a browser that cannot draw one' do
    Themes::NAMES.each do |name|
      palette = Themes.palette(name)
      glow = palette[:glow_ink]

      get settings_url, headers: { 'HTTP_COOKIE' => "theme=#{name}" }

      supports = style_block[/@supports[^{]*\{(.*)\}\s*\z/m, 1]

      if glow.blank?
        assert_nil supports, "#{name} has no glow, so it needs no @supports block"
        next
      end

      assert_includes supports.to_s, "color:#{glow}", "#{name} does not hand back its dim ink"
      # The link is the only thing marking a link on these styles, so the two must differ
      # whichever ink is in force.
      assert_not_equal palette[:link], palette[:ink], "#{name}: the ink matches the link"
      assert_not_equal palette[:link], glow, "#{name}: the dim ink matches the link"
    end
  end

  # The cookie is a string from the client, and it is interpolated into a style block.
  test 'an unrecognised theme falls back to the plain palette rather than reaching the page' do
    get settings_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber%7D%20body%7Bcolor%3Ared' }

    assert_response :success

    assert_match(/<body data-theme="unstyled">/, @response.body)
    # Byte for byte the plain palette, so nothing from the cookie has been carried into it.
    assert_equal Themes.palette('unstyled'), palette_of(style_block)
  end

  # The palette repeats the components' own selectors, so it has to be the later of the
  # two to take effect.
  test 'the palette follows the stylesheet in the head' do
    get settings_url

    assert_operator @response.body.index('<style>'), :>,
                    @response.body.index('stylesheet'),
                    'the palette has to follow the stylesheet link to win on source order'
  end

  private

  def style_block
    @response.body[%r{<style>(.*?)</style>}m, 1]
  end

  # Every declaration in the block, whichever rule it belongs to.
  def declarations(block)
    block.scan(/\{([^}]*)\}/).flatten.flat_map { |body| body.split(';') }
  end

  # The custom property declarations read back as the hash they were written from.
  def palette_of(block)
    block.scan(/--([a-z-]+):([^;}]+)/).to_h { |token, value| [token.tr('-', '_').to_sym, value] }
  end
end
