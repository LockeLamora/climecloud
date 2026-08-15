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
  # Text rendered as a phosphor screen, for the styles whose glow can only reach the
  # handset inside an image. Reads nothing and calls nothing external.
  get 'phosphor' => 'phosphor#text'

  # Everything under one prefix, deliberately: the cookie holding the secrets is scoped to
  # /totp, and the browser only sends it to paths beneath that.
  get 'totp' => 'totp#index'
  get 'totp/code' => 'totp#code'
  get 'totp/add' => 'totp#add'
  get 'totp/backup' => 'totp#backup'
  post 'totp/save' => 'totp#save'
  delete 'totp/forget' => 'totp#forget'

  get 'news' => 'news#news'
  get 'news_article' => 'news#article'
  get 'news_search' => 'news#search'
  # Defines the root path route ("/")
  root 'index#index'
end
