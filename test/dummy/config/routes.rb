Rails.application.routes.draw do
  mount RailsPulse::Engine => "/rails_pulse"

  root "home#index"

  get "fast", to: "home#fast"
  get "slow", to: "home#slow"
  get  "errors",       to: "home#errors"
  post "errors/raise", to: "home#raise_error", as: :raise_error
  get "search", to: "home#search"
  get "api_simple", to: "home#api_simple"
  get "api_complex", to: "home#api_complex"

  get  "jobs",         to: "jobs#index"
  post "jobs/trigger", to: "jobs#trigger", as: :trigger_job
end
