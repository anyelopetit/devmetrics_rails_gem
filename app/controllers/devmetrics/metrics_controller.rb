module Devmetrics
  class MetricsController < ApplicationController
    def index
    end

    def run_tests
      result = ::Devmetrics::RunOrchestrator.call
      if result[:error]
        render json: { error: result[:error] }, status: :unprocessable_entity
      else
        render json: result, status: :accepted
      end
    end

    def run_status
      run = ::Devmetrics::Run.find_by(run_id: params[:run_id])
      return render json: { error: "Not found" }, status: :not_found unless run

      render json: {
        run_id: run.run_id,
        status: run.status,
        files:  run.file_results.map { |r|
          { file_key: r.file_key, file_path: r.file_path, status: r.status,
            coverage: r.coverage, slow_query_count: r.slow_query_count, n1_count: r.n1_count }
        }
      }
    end

    def download_log
      result = ::Devmetrics::FileResult.find_by(
        run_id: params[:run_id], file_key: params[:file_key]
      )
      return render plain: "Not found", status: :not_found unless result&.log_path
      return render plain: "Log not ready", status: :not_found unless File.exist?(result.log_path)

      send_file result.log_path, type: "text/plain", disposition: "attachment"
    end
  end
end
