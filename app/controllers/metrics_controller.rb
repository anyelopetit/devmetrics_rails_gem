class MetricsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :ping, :run_tests ]

  def index
    @recent_slow_queries = SlowQuery.order(created_at: :desc).limit(5)
    @total_queries = QueryLog.count
    @avg_duration = QueryLog.average(:duration)&.round(2) || 0
    @n_plus_one_count = SlowQuery.count
  end

  def ping
    MetricsAnalyzerJob.perform_later
    render json: { status: "ok" }
  end

  def run_tests
    spec_dir = Rails.root.join("spec", "requests")

    unless spec_dir.exist?
      return render json: {
        status: "error",
        message: "No spec/requests directory found. Create request specs tagged with devmetrics_live to run them here."
      }, status: :unprocessable_entity
    end

    # Find spec files that reference devmetrics_live
    spec_files = Dir.glob(spec_dir.join("**", "*_spec.rb")).select do |f|
      File.read(f).include?("devmetrics_live") || File.read(f).include?("DevmetricsLive")
    end

    # Fall back to ALL request specs if none are tagged
    spec_files = Dir.glob(spec_dir.join("**", "*_spec.rb")) if spec_files.empty?

    if spec_files.empty?
      return render json: {
        status: "error",
        message: "No request specs found in spec/requests/. Add some specs to start performance testing."
      }, status: :unprocessable_entity
    end

    run_id = SecureRandom.hex(8)
    PerformanceTestRunnerJob.perform_later(spec_files, run_id)

    render json: { status: "started", run_id: run_id, spec_count: spec_files.size }
  end
end
