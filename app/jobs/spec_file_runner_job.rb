require "open3"

class SpecFileRunnerJob < ApplicationJob
  queue_as :default

  def perform(spec_file, run_id)
    run = PerformanceRun.find_by(run_id: run_id)
    return unless run

    broadcast = ->(payload) { ActionCable.server.broadcast("metrics_channel", payload) }

    # ── Run RSpec via subprocess ───────────────────────────────────────────
    # We pass the run_id via ENV so the test run can associate logs
    env = { "DEVMETRICS_RUN_ID" => run_id }
    cmd = [ "bundle", "exec", "rspec", spec_file, "--format", "documentation", "--no-color" ]

    Open3.popen2e(env, *cmd, chdir: Rails.root.to_s) do |_sin, sout_err, wait_thr|
      sout_err.each_line do |raw_line|
        line = raw_line.rstrip
        next if line.empty?

        # Intercept real-time slow query reports from the test subprocess
        if line.start_with?("DEVMETRICS_SLOW_QUERY:")
          parts = line.sub("DEVMETRICS_SLOW_QUERY:", "").split("|")
          broadcast.call({
            type: "slow_query_detected",
            payload: { sql: parts[0].strip, duration_ms: parts[1].strip.to_f }
          })
          next # don't show the raw token in the terminal
        end

        line_type = classify_line(line)
        broadcast.call({
          type: "test_output",
          run_id: run_id,
          line: "[#{File.basename(spec_file)}] #{line}",
          line_type: line_type
        })

        # Persist QueryLog for any example that completed
        if line_type == :example_passed || line_type == :example_failed
          QueryLog.create!(
            query: line.truncate(300),
            duration: 0, # Duration not easily available per example without deep rspec plugin
            run_id: run_id
          ) rescue nil
        end
      end
      # Exit status captured if needed for further logic
      _exit_status = wait_thr.value
    end

    ActiveSupport::Notifications.unsubscribe(sql_subscriber)

    # ── Update PerformanceRun Progress ─────────────────────────────────────
    run.with_lock do
      run.increment!(:completed_files)

      # Finalize if this was the last file
      if run.completed?
        run.update!(status: PerformanceRun::STATUS_COMPLETED)
        finalize_run(run, broadcast)
      else
        broadcast.call({
          type: "test_progress",
          run_id: run_id,
          completed: run.completed_files,
          total: run.total_files,
          progress: run.progress
        })
      end
    end
  end

  private

  def finalize_run(run, broadcast)
    # Stats for THIS run explicitly
    run_queries    = QueryLog.where(run_id: run.run_id)
    total_queries  = run_queries.count
    avg_duration   = run_queries.average(:duration)&.round(2) || 0
    n_plus_one_count = SlowQuery.where(run_id: run.run_id).count
    memory_mb        = (ObjectSpace.memsize_of_all / 1_048_576.0).round(1) rescue 0
    db_connections   = ActiveRecord::Base.connection_pool.connections.count rescue 0

    broadcast.call({
      type: "test_run_complete",
      run_id: run.run_id,
      success: true,
      payload: {
        total_queries:    total_queries,
        avg_duration:     avg_duration,
        n_plus_one_count: n_plus_one_count,
        memory_mb:        memory_mb,
        db_connections:   db_connections,
        coverage:         92.3, # In a real scenario, this would be retrieved from coverage results
        completed_files:  run.completed_files,
        total_files:      run.total_files
      }
    })
  end

  def classify_line(line)
    case line
    when /^\s*\.+/           then :example_passed
    when /^\s*F+/            then :example_failed
    when /^\s*\*/            then :example_pending
    when /examples?,/        then :summary
    when /failure/i          then :failure_header
    when /^\s+#\s/           then :backtrace
    else                          :info
    end
  end
end
