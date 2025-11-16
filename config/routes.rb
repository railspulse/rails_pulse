RailsPulse::Engine.routes.draw do
  root to: "dashboard#index"

  resources :routes, only: %i[index show]
  resources :requests, only: %i[index show]
  resources :queries, only: %i[index show] do
    member do
      post :analyze
    end
  end
  resources :operations, only: %i[show]
  resources :caches, only: %i[show], as: :cache

  if RailsPulse.configuration.track_jobs
    resources :jobs, only: %i[index show], param: :id do
      resources :runs, only: %i[index show], controller: "job_runs"
    end
  end
  patch "pagination/limit", to: "application#set_pagination_limit"
  patch "settings/global_filters", to: "application#set_global_filters"

  # Tag management
  post "tags/:taggable_type/:taggable_id/add", to: "tags#create", as: :add_tag
  delete "tags/:taggable_type/:taggable_id/remove", to: "tags#destroy", as: :remove_tag

  # CSP compliance testing
  get "csp_test", to: "csp_test#show", as: :csp_test

  # Asset serving fallback
  get "rails-pulse-assets/:asset_name", to: "assets#show", as: :asset, constraints: { asset_name: /.*/ }
end
