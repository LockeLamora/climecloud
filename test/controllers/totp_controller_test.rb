# frozen_string_literal: true

require 'test_helper'
require 'totp'

class TotpControllerTest < ActionDispatch::IntegrationTest
  SECRET = 'JBSWY3DPEHPK3PXP'
  SAVED = [{ 'name' => 'GitHub', 'secret' => SECRET }].to_json

  test 'lists the saved accounts as numbered choices' do
    get totp_url, headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }

    assert_response :success
    assert_match(/<a accesskey="1"[^>]*>1 GitHub/, @response.body)
    assert_match 'Add an account', @response.body
  end

  test 'says so when nothing is saved yet' do
    get totp_url

    assert_response :success
    assert_match 'No accounts saved yet', @response.body
  end

  test 'shows the current code for an account' do
    # A code is only right for its half minute, so if the window turns over mid-test the
    # page is fetched again from inside the fresh one.
    window = Time.now.to_i / Totp::PERIOD
    get totp_code_url(name: 'GitHub'), headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }
    unless Time.now.to_i / Totp::PERIOD == window
      get totp_code_url(name: 'GitHub'), headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }
    end

    code = Totp.code(SECRET)

    assert_response :success
    assert_match "#{code[0, 3]} #{code[3, 3]}", @response.body
    assert_match(/Good for \d+ more seconds/, @response.body)
    # The key itself stays off the page until asked for.
    assert_no_match(/#{SECRET}/, @response.body)
    assert_match 'Show setup key', @response.body
  end

  # This cookie is the only copy of the secret, so there has to be a way to copy it down.
  test 'reveals the stored setup key only when asked' do
    get totp_code_url(name: 'GitHub', reveal: '1'),
        headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }

    assert_response :success
    assert_match SECRET, @response.body
  end

  test 'an account that is not saved goes back to the list rather than erroring' do
    get totp_code_url(name: 'Nowhere'), headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }

    assert_redirected_to totp_path
  end

  # The secrets ride in their own cookie, scoped to /totp, so they travel with these
  # requests and none of the app's others.
  test 'saving writes the separate cookie scoped to its own path' do
    post totp_save_url, params: { name: 'GitHub', secret: 'jbsw y3dp ehpk 3pxp' }

    assert_redirected_to totp_code_path(name: 'GitHub')
    header = @response.headers['Set-Cookie'].to_s

    assert_match(/totp=/, header)
    assert_match(%r{path=/totp}, header)
    assert_match 'JBSWY3DPEHPK3PXP', JSON.parse(CGI.unescape(cookies[:totp])).first['secret']
  end

  test 'saving the same name again replaces the entry rather than doubling it' do
    post totp_save_url, params: { name: 'GitHub', secret: SECRET },
                        headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(SAVED)}" }

    assert_equal 1, JSON.parse(CGI.unescape(cookies[:totp])).length
  end

  test 'rejects a key that cannot be one, and stores nothing' do
    post totp_save_url, params: { name: 'GitHub', secret: 'password123' }

    assert_redirected_to totp_add_path(error: 'secret')
    follow_redirect!

    assert_match 'does not look like a setup key', @response.body
    assert_not cookies[:totp].present?
  end

  test 'rejects a nameless account' do
    post totp_save_url, params: { name: '  ', secret: SECRET }

    assert_redirected_to totp_add_path(error: 'name')
  end

  test 'holds ten accounts and refuses an eleventh' do
    full = (1..10).map { |n| { 'name' => "Site #{n}", 'secret' => SECRET } }.to_json

    post totp_save_url, params: { name: 'Eleventh', secret: SECRET },
                        headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(full)}" }

    assert_redirected_to totp_add_path(error: 'full')
  end

  test 'forgets one account and keeps the rest' do
    two = [{ 'name' => 'GitHub', 'secret' => SECRET },
           { 'name' => 'Mastodon', 'secret' => SECRET }].to_json

    delete totp_forget_url(name: 'GitHub'), headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(two)}" }

    assert_redirected_to totp_path
    remaining = JSON.parse(CGI.unescape(cookies[:totp]))

    assert_equal(['Mastodon'], remaining.map { |account| account['name'] })
  end

  test 'the menu offers 2FA above settings, and glyphs it on a phosphor style' do
    get root_url, headers: { 'HTTP_COOKIE' => 'lat=51.5;city=Testville' }

    assert_operator @response.body.index('7 2FA codes'), :<, @response.body.index('8 Change settings')

    get root_url, headers: { 'HTTP_COOKIE' => 'theme=crt-amber;lat=51.5;city=Testville' }

    assert_match %r{<a accesskey="7"[^>]*><img src="/phosphor\?s=crt-amber&amp;t=7\+2FA\+codes"},
                 @response.body
  end

  # The cookie is the only copy of every secret, and a backup that takes ten separate
  # presses is one that never happens: one page carries every name and key for writing
  # down. Offered only when there is something to back up.
  test 'one page shows every setup key for manual backup' do
    two = [{ 'name' => 'GitHub', 'secret' => SECRET },
           { 'name' => 'Mastodon', 'secret' => 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }].to_json

    get totp_url, headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(two)}" }

    assert_match 'Show all setup keys', @response.body

    get totp_backup_url, headers: { 'HTTP_COOKIE' => "totp=#{CGI.escape(two)}" }

    assert_response :success
    assert_match 'Write these down', @response.body
    assert_match 'GitHub', @response.body
    assert_match SECRET, @response.body
    assert_match 'Mastodon', @response.body
    assert_match 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', @response.body
  end

  test 'the backup page is not offered while there is nothing to back up' do
    get totp_url

    assert_no_match(/Show all setup keys/, @response.body)
  end

  # A mangled cookie is a fresh start, not a crash.
  test 'an unreadable cookie reads as no accounts' do
    get totp_url, headers: { 'HTTP_COOKIE' => 'totp=not-json' }

    assert_response :success
    assert_match 'No accounts saved yet', @response.body
  end
end
