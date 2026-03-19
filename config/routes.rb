Rails.application.routes.draw do
  scope "/devmetrics", module: "devmetrics", as: "devmetrics" do
    root "metrics#index"

    post "run_tests",                            to: "metrics#run_tests"
    get  "runs/:run_id/status",                  to: "metrics#run_status"
    get  "runs/:run_id/logs/:file_key/download", to: "metrics#download_log"

    get  "playground",     to: "playground#run"
    post "playground/run", to: "playground#run"
  end

  get "/", to: redirect("/devmetrics")
  get "/up", to: "rails/health#show"

  mount ActionCable.server => "/devmetrics/cable"
end
