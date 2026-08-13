# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'settings' => 'settings#change'
  # Storing a location and choosing a language both change what is saved, so neither can
  # be a GET: see the note on departures_save below.
  post 'settings_save' => 'settings#set'
  post 'settings_language' => 'settings#language'
  # Read only. It re-runs the postcode search to show what else matched and stores
  # nothing, so it stays a link.
  get 'settings_pick' => 'settings#pick'
  get 'forecast/hourly' => 'forecast#hourly'
  get 'forecast/daily' => 'forecast#daily'

  get 'directions' => 'directions#search'
  get 'directions_plan' => 'directions#plan'
  get 'directions_pick' => 'directions#pick'
  get 'departures' => 'departures#index'
  get 'departures_stop' => 'departures#stop'
  get 'departures_add' => 'departures#add'
  # Not GET. These two change what is saved, and a GET that changes something is fetched
  # by anything that guesses at links before they are followed.
  post 'departures_save' => 'departures#save'
  delete 'departures_forget' => 'departures#forget'

  get 'places' => 'places#index'
  get 'places_list' => 'places#list'
  get 'places_search' => 'places#search'
  delete 'places_forget' => 'places#forget'
  get 'wikipedia' => 'wikipedia#search'
  get 'wikipedia_article' => 'wikipedia#article'
  get 'news' => 'news#news'
  get 'news_article' => 'news#article'
  get 'news_search' => 'news#search'
  # Defines the root path route ("/")
  root 'index#index'
end
