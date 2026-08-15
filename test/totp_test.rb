# frozen_string_literal: true

require 'test_helper'
require 'totp'

class TotpTest < ActiveSupport::TestCase
  # RFC 6238's own test secret: the ASCII bytes "12345678901234567890", which is
  # GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ in the Base32 a site's setup key uses.
  RFC_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'

  # The RFC's Appendix B vectors, truncated from its eight digits to the six every
  # mainstream site asks for.
  test 'produces the RFC 6238 test vectors' do
    assert_equal '287082', Totp.code(RFC_SECRET, at: Time.at(59))
    assert_equal '081804', Totp.code(RFC_SECRET, at: Time.at(1_111_111_109))
    assert_equal '005924', Totp.code(RFC_SECRET, at: Time.at(1_234_567_890))
    assert_equal '279037', Totp.code(RFC_SECRET, at: Time.at(2_000_000_000))
  end

  test 'a code holds for its half minute and changes at the boundary' do
    assert_equal Totp.code(RFC_SECRET, at: Time.at(30)), Totp.code(RFC_SECRET, at: Time.at(59))
    assert_not_equal Totp.code(RFC_SECRET, at: Time.at(59)), Totp.code(RFC_SECRET, at: Time.at(60))
  end

  # A setup key as sites actually display it: lowercase, grouped, sometimes padded.
  test 'normalises the shapes a site displays its key in' do
    assert_equal 'JBSWY3DPEHPK3PXP', Totp.normalise('jbsw y3dp ehpk 3pxp')
    assert_equal 'JBSWY3DPEHPK3PXP', Totp.normalise('JBSW-Y3DP-EHPK-3PXP')
    assert_equal 'JBSWY3DPEHPK3PXP', Totp.normalise("JBSWY3DPEHPK3PXP==\n")
  end

  test 'rejects what cannot be a setup key' do
    assert_not Totp.valid?(Totp.normalise('password123')), '0, 1, 8 and 9 are not Base32'
    assert_not Totp.valid?(Totp.normalise('JBSWY3DP')), 'shorter than any real key'
    assert_not Totp.valid?(Totp.normalise('')), 'nothing at all'
    assert Totp.valid?(Totp.normalise('jbsw y3dp ehpk 3pxp'))
  end

  # Two groups of four to a row: how the sites display keys, and narrow enough that no
  # row can run off a 240px screen.
  test 'lays a key out in rows a hand can copy' do
    assert_equal ['JBSW Y3DP', 'EHPK 3PXP'], Totp.rows('JBSWY3DPEHPK3PXP')
    assert_equal 4, Totp.rows(RFC_SECRET).length
    assert_operator Totp.rows(RFC_SECRET).map(&:length).max, :<=, 9
  end

  test 'the seconds remaining count down the period' do
    assert_equal 30, Totp.seconds_remaining(at: Time.at(0))
    assert_equal 1, Totp.seconds_remaining(at: Time.at(29))
  end
end
