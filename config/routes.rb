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

  # The gamebooks ship with the app and read nothing external. Reading a section notes
  # the place in the CYOA cookie — client-side state like every other setting, so these
  # GETs still store nothing on the server.
  get 'games' => 'games#index'
  get 'games/:book' => 'games#book', as: :games_book
  get 'games/:book/:section' => 'games#section', as: :games_section

  get 'news' => 'news#news'
  get 'news_article' => 'news#article'
  get 'news_search' => 'news#search'
  # Defines the root path route ("/")
  root 'index#index'
end
