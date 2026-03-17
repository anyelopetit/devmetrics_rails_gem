class PerformanceTestRunnerJob < ApplicationJob
  queue_as :default

  def perform(spec_files, run_id)
    broadcast = ->(payload) { ActionCable.server.broadcast("metrics_channel", payload) }

    run = PerformanceRun.create!(
      run_id: run_id,
      total_files: spec_files.size,
      completed_files: 0,
      status: PerformanceRun::STATUS_RUNNING
    )

    broadcast.call({
      type: "test_run_started",
      run_id: run_id,
      spec_count: spec_files.size,
      progress: run.progress
    })

    spec_files.each do |spec_file|
      SpecFileRunnerJob.perform_later(spec_file, run_id)
    end
  end
end
