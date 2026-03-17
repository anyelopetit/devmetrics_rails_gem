class PerformanceRun < ApplicationRecord
  STATUS_PENDING   = "pending".freeze
  STATUS_RUNNING   = "running".freeze
  STATUS_COMPLETED = "completed".freeze
  STATUS_FAILED    = "failed".freeze

  def progress
    return 0 if total_files.to_i.zero?
    ((completed_files.to_f / total_files.to_f) * 100).round(1)
  end

  def completed?
    completed_files.to_i >= total_files.to_i
  end
end
