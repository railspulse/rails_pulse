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
  patch "pagination/limit", to: "application#set_pagination_limit"

  # CSP compliance testing
  get "csp_test", to: "csp_test#show", as: :csp_test

  # Asset serving fallback
  get "rails-pulse-assets/:asset_name", to: "assets#show", as: :asset, constraints: { asset_name: /.*/ }
end
