Rails.application.routes.draw do
  root 'home#index'
  
  get 'fast', to: 'home#fast'
  get 'slow', to: 'home#slow'
  get 'error_prone', to: 'home#error_prone'
  get 'search', to: 'home#search'
  get 'api_simple', to: 'home#api_simple'
  get 'api_complex', to: 'home#api_complex'
  
  mount RailsPulse::Engine => "/rails_pulse"
end
