Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "settings" => "settings#change"
  get "settings_save" => "settings#set"
  get "forecast/hourly" => "forecast#hourly"
  get "forecast/daily" => "forecast#daily"

  get "directions" => "directions#search"
  get "directions_plan" => "directions#plan"
  get "news" => "news#news"
  # Defines the root path route ("/")
  root "index#index"
end
