module Devmetrics
  class FileResult < ActiveRecord::Base
    self.table_name = "devmetrics_file_results"

    enum status: { pending: 0, running: 1, passed: 2, failed: 3 }

    belongs_to :run, foreign_key: :run_id, primary_key: :run_id,
               class_name: "Devmetrics::Run"

    def self.file_key_for(file_path)
      File.basename(file_path, ".rb").gsub(/[^a-z0-9_]/, "_")
    end
  end
end
