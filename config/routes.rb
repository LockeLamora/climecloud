# frozen_string_literal: true

Rails.application.routes.draw do
  # Anything that changes what is stored is a POST or a DELETE. A GET is fetched by
  # browsers and crawlers that follow links speculatively, so a GET must only ever read.
  get 'settings' => 'settings#change'
  post 'settings_save' => 'settings#set'
  post 'settings_language' => 'settings#language'
  # Reads only: re-runs the postcode search to show what else matched.
  get 'settings_pick' => 'settings#pick'
  get 'forecast/hourly' => 'forecast#hourly'
  get 'forecast/daily' => 'forecast#daily'

  get 'directions' => 'directions#search'
  get 'directions_plan' => 'directions#plan'
  get 'directions_pick' => 'directions#pick'
  get 'departures' => 'departures#index'
  get 'departures_stop' => 'departures#stop'
  get 'departures_add' => 'departures#add'
  post 'departures_save' => 'departures#save'
  delete 'departures_forget' => 'departures#forget'

  get 'places' => 'places#index'
  get 'places_list' => 'places#list'
  get 'places_search' => 'places#search'
  post 'places_save' => 'places#save'
  delete 'places_forget' => 'places#forget'
  get 'wikipedia' => 'wikipedia#search'
  get 'wikipedia_article' => 'wikipedia#article'
  # Text rendered as an image — a phosphor screen, or a machine's own character set — for
  # the styles whose look can only reach the handset that way. Reads nothing and calls
  # nothing external.
  get 'glyph' => 'glyph#text'

  # Everything under one prefix, deliberately: the cookie holding the secrets is scoped to
  # /totp, and the browser only sends it to paths beneath that.
  get 'totp' => 'totp#index'
  get 'totp/code' => 'totp#code'
  get 'totp/add' => 'totp#add'
  get 'totp/backup' => 'totp#backup'
  get 'totp/confirm' => 'totp#confirm'
  get 'totp/note' => 'totp#note'
  post 'totp/save' => 'totp#save'
  post 'totp/save_note' => 'totp#save_note'
  delete 'totp/forget' => 'totp#forget'
  delete 'totp/forget_all' => 'totp#forget_all'

  # The gamebooks ship with the app and read nothing external. Turning a page is a POST
  # because it moves the bookmark in the CYOA cookie: a browser that prefetches whatever
  # the cursor passes must not turn pages the reader never chose. The section GET below
  # it is a pure read, so a prefetch of it costs nothing.
  get 'games' => 'games#index'

  # The little games: every view a pure read, every move a POST, all state in a small
  # cookie of its own like the CYOA bookmark. Named before the book routes below, or
  # games/:book would swallow them.
  get 'card/:code' => 'card#show', as: :playing_card
  get 'games/hilo' => 'hilo#show', as: :games_hilo
  post 'games/hilo/guess' => 'hilo#guess'
  get 'games/pontoon' => 'pontoon#show', as: :games_pontoon
  post 'games/pontoon/deal' => 'pontoon#deal'
  post 'games/pontoon/twist' => 'pontoon#twist'
  post 'games/pontoon/stick' => 'pontoon#stick'
  post 'games/pontoon/reset' => 'pontoon#reset'
  get 'games/trader' => 'trader#show', as: :games_trader
  get 'games/trader/sail' => 'trader#sail', as: :games_trader_sail
  post 'games/trader/trade' => 'trader#trade'
  post 'games/trader/go' => 'trader#go'
  post 'games/trader/pay' => 'trader#pay'
  post 'games/trader/retire' => 'trader#retire'
  get 'games/journey' => 'journey#show', as: :games_journey
  post 'games/journey/act' => 'journey#act'
  post 'games/journey/restart' => 'journey#restart'
  get 'games/riddle' => 'riddle#show', as: :games_riddle
  post 'games/riddle/answer' => 'riddle#answer'

  get 'games/:book' => 'games#book', as: :games_book
  post 'games/turn' => 'games#turn'
  post 'games/restart' => 'games#restart'
  post 'games/use' => 'games#use'
  post 'games/take' => 'games#take'
  get 'games/:book/:section' => 'games#section', as: :games_section

  get 'news' => 'news#news'
  get 'news_article' => 'news#article'
  # A headline is a link like every other list entry, so the handset's cursor stops on
  # it once and the drawn styles keep their glyphs — but its GET lands here, an instant
  # redirect that itself calls nothing. A reader's browser follows the redirect to the
  # article in the same press; whether the handset's prefetcher follows it too is what
  # the logs will say — a news_open hit with no article render after it means the
  # prefetcher stopped at the redirect and spent nothing.
  get 'news_open' => 'news#open'
  get 'news_search' => 'news#search'
  # Defines the root path route ("/")
  root 'index#index'
end
