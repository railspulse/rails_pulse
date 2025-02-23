RailsPulse::Engine.routes.draw do
  root to: "dashboard#index"

  resources :routes, only: %i[index show]
  resources :requests, only: %i[index show]
  resources :queries, only: %i[index show]
  resources :operations, only: %i[show]
  resources :metric_cards, only: %i[show]
  patch 'pagination/limit', to: 'application#set_pagination_limit'
end
