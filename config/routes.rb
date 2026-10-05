RailsPulse::Engine.routes.draw do
  root to: "dashboard#index"

  resources :routes, only: %i[index show]
  resources :requests, only: %i[index show]
  resources :queries, only: %i[index show] do
    member do
      post :reanalyze
    end
  end
  resources :operations, only: %i[show]
  if RailsPulse.configuration.track_exceptions
    resources :exceptions, only: %i[index show update] do
      resources :occurrences, only: %i[show], controller: "exception_occurrences"
    end
  end

  if RailsPulse.configuration.track_jobs
    resources :jobs, only: %i[index show], param: :id do
      resources :runs, only: %i[index show], controller: "job_runs"
    end
  end
  resource :storage, only: :show, controller: "storage"
  patch "pagination/limit", to: "application#set_pagination_limit", as: :pagination_limit
  patch "settings/global_filters", to: "application#set_global_filters", as: :settings_global_filters
  patch "settings/time_range", to: "application#set_time_range", as: :settings_time_range

  # Tag management
  post "tags/:taggable_type/:taggable_id/add", to: "tags#create", as: :add_tag
  delete "tags/:taggable_type/:taggable_id/remove", to: "tags#destroy", as: :remove_tag

  # Deployments are both an API endpoint for CI/CD and a browsable record of
  # what shipped when.
  resources :deployments, only: %i[index show create] do
    collection do
      put :finish
    end
  end

  # Read-only JSON API for the rails-pulse CLI, the MCP server and CI, all
  # authenticated by config.api_token (app/controllers/rails_pulse/api/v1).
  scope path: "api/v1", module: "api/v1", as: :api_v1 do
    resources :routes,      only: :index
    resources :requests,    only: :index
    resources :queries,     only: :index
    resources :jobs,        only: :index
    resources :job_runs,    only: :index
    resources :deployments, only: :index
    resources :exceptions,  only: %i[index show]

    # Whether the data is there, rather than a question about the data.
    get "coverage", to: "coverage#show", as: :coverage

    # What needs attention over one summary period, and whether the
    # thresholds fit it.
    get "insights", to: "insights#show", as: :insights

    # Which application, environment and version answered, so results gathered
    # against staging are not read as production.
    get "capabilities", to: "capabilities#show", as: :capabilities
  end

  # CSP compliance testing (development/test only)
  if Rails.env.local?
    get "csp_test", to: "csp_test#show", as: :csp_test
  end

  # Asset serving fallback
  get "rails-pulse-assets/:asset_name", to: "assets#show", as: :asset, constraints: { asset_name: /.*/ }
end
