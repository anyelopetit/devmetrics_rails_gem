Devmetrics::Engine.routes.draw do
  root to: "metrics#index"

  get "/metrics", to: "metrics#index"
  post "/run_tests", to: "metrics#run_tests"

  get "/playground", to: "playground#run"
  post "/playground/run", to: "playground#run"

  get "/up", to: "rails/health#show", as: :health
end
