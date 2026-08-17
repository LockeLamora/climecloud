# frozen_string_literal: true

require 'totp'

# Two-factor codes for the accounts a reader has keyed in, held like everything else here:
# client-side, in a cookie, with the server storing nothing. The server's part is the
# arithmetic — the handset's clock drifts, and a code cut from the wrong half-minute is
# refused — and the secret it computes from is the reader's own cookie riding the request.
#
# The cookie is scoped to /totp, so the secrets ride only the requests to these pages
# rather than every fetch of a headline or a glyph. That is also why every route here
# lives under the /totp prefix: the browser withholds the cookie anywhere else.
class TotpController < ApplicationController
  # Comfortably inside the 4KB a cookie holds even with long names and long keys, and far
  # past what anyone enrols by keypad.
  MAX_ACCOUNTS = 30
  # The digits 1 to 6 select an account; 7 turns the page and 8, 9 and 0 are the fixed
  # actions, so six is what one screen can offer a keypad.
  PER_PAGE = 6
  # What save can refuse, named so the locale check can enumerate totp.error.* keys.
  ERRORS = %w[name secret full].freeze

  def index
    @page = [params[:page].to_i, 0].max
    @accounts = accounts.slice(@page * PER_PAGE, PER_PAGE) || []
    @any = accounts.any?
    @more = accounts.length > (@page + 1) * PER_PAGE
  end

  # The one question a slip must pass through before a secret is gone: forgetting a code
  # here is being locked out of the account it guards, not retyping a bus stop.
  def confirm
    @name = params[:name].presence
  end

  def code
    @account = accounts.find { |account| account['name'] == params[:name] }
    if @account.nil?
      redirect_to totp_path
      return
    end

    @code = Totp.code(@account['secret'])
    @seconds = Totp.seconds_remaining
    # The stored secret, shown only when asked for: losing this cookie means losing the
    # account's second factor, so there has to be a way to copy it down or re-enrol it.
    @reveal = params[:reveal].present?
  end

  def add
    @error = params[:error]
  end

  # Every name and key on one page, for writing down: the cookie is the only copy of these
  # secrets, and a backup that takes ten separate presses is one that never happens.
  def backup
    @accounts = accounts
  end

  def save
    secret = Totp.normalise(params[:secret])
    name = params[:name].to_s.squish
    error = save_error(name, secret)
    if error
      # The form again with the attempt still in it: a mistyped key is one wrong character,
      # and retyping thirty-one right ones to fix it is keypad punishment. Rendered rather
      # than redirected, so the typed secret stays in the filtered POST body and never
      # lands in a logged URL.
      @error = error
      @name = params[:name]
      @secret = params[:secret]
      render :add
      return
    end

    entry = { 'name' => name, 'secret' => secret }
    write_accounts([entry] + accounts.reject { |account| account['name'] == name })
    redirect_to totp_code_path(name: name)
  end

  # Reached only through confirm, both of them: the views link there and nowhere posts
  # here directly.
  def forget
    write_accounts(accounts.reject { |account| account['name'] == params[:name] })
    redirect_to totp_path
  end

  def forget_all
    cookies.delete(:totp, path: '/totp')
    redirect_to totp_path
  end

  private

  def accounts
    JSON.parse(cookies[:totp].presence || '[]')
  rescue JSON::ParserError
    []
  end

  def write_accounts(entries)
    cookies.permanent[:totp] = { value: entries.first(MAX_ACCOUNTS).to_json, path: '/totp' }
  end

  def save_error(name, secret)
    return 'name' if name.blank?
    return 'secret' unless Totp.valid?(secret)
    return 'full' if accounts.length >= MAX_ACCOUNTS && accounts.none? { |a| a['name'] == name }

    nil
  end
end
