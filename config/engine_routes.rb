Devmetrics::Engine.routes.draw do
  root to: "metrics#index"

  post "run_tests",                            to: "metrics#run_tests"
  get  "runs/:run_id/status",                  to: "metrics#run_status"
  get  "runs/:run_id/logs/:file_key/download", to: "metrics#download_log"

  get  "playground",     to: "playground#run"
  post "playground/run", to: "playground#run"
end
