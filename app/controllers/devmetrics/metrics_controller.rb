module Devmetrics
  class MetricsController < ApplicationController
    def index
      @log_content = if File.exist?(Devmetrics.log_path)
                       File.read(Devmetrics.log_path)
                     else
                       "No performance tests run yet. Run the tests to generate results."
                     end
    end

    def run_tests
      spec_dir = Rails.root.join("spec", "requests")

      unless spec_dir.exist?
        return render json: {
          status: "error",
          message: "No spec/requests directory found. Create request specs to run them here."
        }, status: :unprocessable_entity
      end

      # Find spec files that reference devmetrics tagline
      spec_files = Dir.glob(spec_dir.join("**", "*_spec.rb")).select do |f|
        File.read(f).include?("devmetrics: true") || File.read(f).include?("Devmetrics")
      end

      # Fallback to all request specs if none are tagged
      spec_files = Dir.glob(spec_dir.join("**", "*_spec.rb")) if spec_files.empty?

      if spec_files.empty?
        return render json: {
          status: "error",
          message: "No request specs found in spec/requests/. Add some specs to start performance testing."
        }, status: :unprocessable_entity
      end

      # Execute rspec synchronously with tracking enabled
      command = "DEVMETRICS_TRACKING=true bundle exec rspec #{spec_files.join(' ')} --no-color"
      output = `#{command}`

      # Read the resulting log file
      results = if File.exist?(Devmetrics.log_path)
                  File.read(Devmetrics.log_path)
                else
                  "Error during test execution. Please check the console output:\n#{output}"
                end

      render json: { status: "finished", spec_count: spec_files.size, results: results }
    end
  end
end
