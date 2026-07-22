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

  get  "sign_in", to: "home#index"
  post "sign_in", to: "home#index"

  # Simulate Devise/Warden constraints that touch request env (used by RouteRecognizer tests).
  constraints(->(req) { req.env["warden"].authenticated? }) do
    get "warden_protected", to: "home#index"
  end
  constraints(->(req) { !req.env["warden"].authenticated? }) do
    get "warden_public", to: "home#index"
  end

  get "posts", to: "home#index", as: :posts
  get "posts/:id", to: "home#index", as: :post
  get "partners/:client_id/submissions/:uuid", to: "home#index", as: :partner_submission
end
