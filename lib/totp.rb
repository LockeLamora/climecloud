# frozen_string_literal: true

require 'rotp'

# Time-based one-time passwords for the 2FA page: six digits over a thirty second period
# with HMAC-SHA1, which is what every site's "can't scan the code?" setup key expects. The
# arithmetic is ROTP's — the one OTP library the Ruby ecosystem has audited for a decade —
# and this module is the app's face on it: what a key looks like as a site displays one,
# and what of it is worth storing.
#
# The clock is this server's, which is the right one: the handset's own clock drifts, and a
# code cut from the wrong half-minute is refused by the site asking for it.
module Totp
  DIGITS = 6
  PERIOD = 30

  # A setup key as a site displays it: often lowercase, grouped with spaces or dashes, and
  # sometimes padded with '='. All of that is presentation; this is the secret itself.
  def self.normalise(input)
    input.to_s.gsub(/[\s-]/, '').delete('=').upcase
  end

  # Sixteen Base32 characters is the shortest key any mainstream site issues; sixty-four
  # covers the longest. Anything else is a typo sooner than a secret.
  def self.valid?(secret)
    secret.match?(/\A[A-Z2-7]{16,64}\z/)
  end

  def self.code(secret, at: Time.now)
    ROTP::TOTP.new(secret, digits: DIGITS, interval: PERIOD).at(at)
  end

  # How long the code on screen stays right, so the page can say whether it is worth
  # typing or worth refreshing first.
  def self.seconds_remaining(at: Time.now)
    PERIOD - (at.to_i % PERIOD)
  end

  # A key laid out for copying by hand: groups of four, two to a row, which is how the
  # sites display theirs. Left whole it is one unbroken word that nothing can wrap, and it
  # runs off the side of a narrow screen.
  def self.rows(secret)
    secret.scan(/.{1,4}/).each_slice(2).map { |pair| pair.join(' ') }
  end
end
