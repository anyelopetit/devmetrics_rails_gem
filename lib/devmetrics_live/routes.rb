DevmetricsLive::Engine.routes.draw do
  root to: "metrics#index"

  get  "/",          to: "metrics#index"
  post "/ping",      to: "metrics#ping"
  post "/run_tests", to: "metrics#run_tests"

  get  "/playground", to: "playground#run"
  post "/playground", to: "playground#run"
end
