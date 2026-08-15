# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'cgi'

# A second route to a service that has refused us on a rate limit.
#
# Open-Meteo and Google News both count their free allowance against the calling IP, and
# this app shares an outbound address with everything else on the host, so the allowance
# can be gone through no fault of the reader in front of it. A relay gives the request one
# more chance from a different address.
#
# Only ever after a 429. Any other refusal is our own bad request, and relaying it would
# just be wrong twice.
module Relay
  RATE_LIMITED = '429'

  # Ordered by what answers most reliably. A relay that is down today may be up next month,
  # so a dead one stays on the list; the timeout and budget below are what keep it from
  # costing the reader anything much. Every attempt is logged, so a relay that has stopped
  # answering is visible rather than silently absorbed.
  #
  # Not every relay takes its target the same way: one wants it in the path unescaped, the
  # others want it escaped in a query string, and the first needs a header or it returns
  # the page dressed up for a language model rather than the body we asked for.
  PROXIES = [
    { template: 'https://r.jina.ai/%<url>s',
      escape: false,
      headers: { 'x-return-format' => 'text' } },
    { template: 'https://api.allorigins.win/raw?url=%<url>s', escape: true, headers: {} },
    { template: 'https://api.codetabs.com/v1/proxy?quest=%<url>s', escape: true, headers: {} }
  ].freeze

  # Short, because a stalled relay must not cost more than the page is worth.
  TIMEOUT_SECONDS = 4
  # A ceiling across all of them together, so adding a relay to the list does not add
  # another timeout to the wait before the reader is told the service is busy.
  BUDGET_SECONDS = 10

  # What a caller can spend where something else is already waiting on it.
  #
  # Opera Mini fetches a page through Opera's own servers, and those give up on a request
  # that takes too long: the handset is then told the page could not be opened, which is
  # worse than any answer the page could have carried. A relay run that spends the full
  # budget above puts a page over ten seconds behind Google's own refusal, so a caller
  # sitting in front of a reader passes something tighter and takes fewer chances.
  IMPATIENT_TIMEOUT_SECONDS = 2
  IMPATIENT_BUDGET_SECONDS = 5

  # Each relay in turn until one returns a body the caller can use.
  #
  # The block is handed the body and returns what it read out of it, or nil if the body is
  # no good — a relay that rewrote the content, an error page, a truncated response. That
  # is the only test of a relay's answer, and it has to be the caller's: a relay reports its
  # own success, not the target's, so a 200 here means nothing on its own.
  #
  # subject names the caller in the log, so a relay failure is not read as the service
  # behind it being busy.
  def self.fetch(uri, subject:, impatient: false, &usable)
    timeout = impatient ? IMPATIENT_TIMEOUT_SECONDS : TIMEOUT_SECONDS
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
               (impatient ? IMPATIENT_BUDGET_SECONDS : BUDGET_SECONDS)

    PROXIES.each do |proxy|
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Rails.logger.warn("#{subject} relays gave up - budget spent")
        break
      end

      value = attempt(proxy, uri, subject, timeout, &usable)
      next if value.nil?

      Rails.logger.info("#{subject} relayed by #{host(proxy)}")
      return value
    end

    Rails.logger.warn("#{subject} unavailable - #{PROXIES.length} relays tried, none answered")
    nil
  end

  # Logged either way. A relay is somebody else's free service and will eventually stop
  # answering, and the line here names which one.
  def self.attempt(proxy, uri, subject, timeout)
    res = get_with_timeout(proxy_uri(proxy, uri), proxy[:headers], subject, timeout)
    # Nothing came back at all, and the rescue that caught it has already said why.
    return nil if res.nil?
    return failed(proxy, subject, "response #{res.code}") unless res.is_a?(Net::HTTPSuccess)

    value = yield(res.body)
    return failed(proxy, subject, 'nothing usable in the body') if value.nil?

    value
  end

  def self.proxy_uri(proxy, uri)
    target = proxy[:escape] ? CGI.escape(uri.to_s) : uri.to_s

    URI(format(proxy[:template], url: target))
  end

  def self.failed(proxy, subject, reason)
    Rails.logger.warn("#{subject} relay #{host(proxy)} failed - #{reason}")
    nil
  end

  def self.host(proxy)
    URI(format(proxy[:template], url: '')).host
  end

  # A relay that hangs would leave the phone waiting on a page that may never come, so
  # anything going wrong here is simply the next relay's turn.
  def self.get_with_timeout(uri, headers, subject, timeout)
    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: timeout,
                    read_timeout: timeout) do |http|
      http.request(Net::HTTP::Get.new(uri, headers))
    end
  rescue StandardError => e
    Rails.logger.warn("#{subject} relay #{uri.host} unreachable - #{e.class}")
    nil
  end

  private_class_method :attempt, :proxy_uri, :failed, :host, :get_with_timeout
end
