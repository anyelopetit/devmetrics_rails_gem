module Devmetrics
  class Run < ActiveRecord::Base
    self.table_name = "devmetrics_runs"

    enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }

    has_many :file_results, foreign_key: :run_id, primary_key: :run_id,
             class_name: "Devmetrics::FileResult"

    def self.create_for_files(file_paths)
      create!(
        run_id:      SecureRandom.hex(8),
        status:      :running,
        started_at:  Time.current,
        total_files: file_paths.size
      )
    end
  end
end
