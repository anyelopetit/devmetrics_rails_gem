module Devmetrics
  class FileRunnerJob < ActiveJob::Base
    queue_as :devmetrics

    SLOW_THRESHOLD_MS = -> { Devmetrics.configuration.slow_query_threshold_ms }

    def perform(run_id:, file_path:, file_key:)
      result = ::Devmetrics::FileResult.find_by!(run_id: run_id, file_key: file_key)
      result.update!(status: :running)

      log    = ::Devmetrics::LogWriter.open(run_id, file_key)
      stream = "devmetrics:file:#{file_key}:#{run_id}"

      broadcast(stream, type: "file_started", file_key: file_key)

      ::Devmetrics::SqlInstrumentor.around_run do
        run_rspec(file_path, stream, log, result)
      end

      flush_sql_results(stream, log, result)
      write_coverage(stream, log, result, file_path)
      finalize(stream, log, result, run_id)
    rescue => e
      broadcast(stream, type: "file_error", message: e.message)
      result&.update!(status: :failed)
    ensure
      log&.close
    end

    private

    def run_rspec(file_path, stream, log, result)
      cmd = [
        "bundle", "exec", "rspec", file_path,
        "--format", "documentation",
        "--format", "json",
        "--out", json_output_path(result.run_id, result.file_key)
      ]

      passed = 0
      failed = 0
      start  = Time.current

      Open3.popen2e(*cmd, chdir: Rails.root.to_s) do |_stdin, stdout_err, wait_thr|
        stdout_err.each_line do |raw_line|
          line = raw_line.chomp
          log.write(line)

          event_type = classify_line(line)
          broadcast(stream, type: "test_output", line: line, event_type: event_type)

          passed += 1 if event_type == "pass"
          failed += 1 if event_type == "fail"
        end

        exit_status = wait_thr.value
        status = exit_status.success? && failed == 0 ? :passed : :failed
        result.update!(
          status:       status,
          passed_tests: passed,
          failed_tests: failed,
          total_tests:  passed + failed,
          duration_ms:  ((Time.current - start) * 1000).round
        )
      end
    end

    def flush_sql_results(stream, log, result)
      queries   = ::Devmetrics::SqlInstrumentor.queries
      slow      = queries.select { |q| q[:ms] >= SLOW_THRESHOLD_MS.call }
      n1_groups = detect_n1_patterns(queries)

      slow.each do |q|
        entry = { sql: q[:sql].truncate(200), ms: q[:ms] }
        log.write("  [SLOW #{q[:ms]}ms] #{q[:sql].truncate(120)}")
        broadcast(stream, type: "slow_query", query: entry)

        ::Devmetrics::SlowQuery.create!(
          run_id:      result.run_id,
          file_key:    result.file_key,
          sql:         q[:sql],
          duration_ms: q[:ms]
        )
      end

      n1_groups.each do |pattern, count|
        msg = "N+1 detected: #{pattern} (#{count}x) — add includes(:#{n1_association(pattern)})"
        log.write("  [N+1] #{msg}")
        broadcast(stream, type: "n1_detected", message: msg, pattern: pattern, count: count)
      end

      result.update!(
        slow_query_count: slow.size,
        n1_count:         n1_groups.size
      )
    end

    def write_coverage(stream, log, result, file_path)
      json_path = json_output_path(result.run_id, result.file_key)
      return unless File.exist?(json_path)

      data    = JSON.parse(File.read(json_path)) rescue {}
      summary = data.dig("summary", "example_count")
      return unless summary

      resultset_path = Rails.root.join("coverage", ".resultset.json")
      if File.exist?(resultset_path)
        rs  = JSON.parse(File.read(resultset_path)) rescue {}
        pct = extract_coverage_pct(rs, file_path)
        if pct
          log.write("  [COVERAGE] #{pct.round(1)}%")
          broadcast(stream, type: "coverage_update", pct: pct.round(1))
          result.update!(coverage: pct.round(1))
        end
      end
    end

    def finalize(stream, log, result, run_id)
      log.write("")
      log.write("=" * 60)
      log.write("Result: #{result.status.upcase}  |  " \
                "#{result.total_tests} tests, #{result.failed_tests} failures  |  " \
                "#{result.slow_query_count} slow queries  |  #{result.n1_count} N+1 issues")

      result.update!(log_path: log.path)

      broadcast(stream, type: "file_complete",
        status:      result.status,
        passed:      result.passed_tests,
        failed:      result.failed_tests,
        slow_count:  result.slow_query_count,
        n1_count:    result.n1_count,
        coverage:    result.coverage,
        duration_ms: result.duration_ms,
        log_path:    result.log_path
      )

      run = ::Devmetrics::Run.find_by(run_id: run_id)
      if run
        run.with_lock do
          run.increment!(:completed_files)
          if run.completed_files >= run.total_files
            run.update!(status: :completed, finished_at: Time.current)
            ActionCable.server.broadcast(
              "devmetrics:run:#{run_id}",
              type:        "run_complete",
              run_id:      run_id,
              total_files: run.total_files
            )
            write_run_summary(run)
          end
        end
      end
    end

    def broadcast(stream, payload)
      ActionCable.server.broadcast(stream, payload)
    end

    def classify_line(line)
      if line.match?(/^\s+\d+ examples?,/)
        "summary"
      elsif line.match?(/^\s*[·.]\s/) || line.strip.start_with?(".")
        "pass"
      elsif line.match?(/^\s*[F!]\s/) || line.strip.start_with?("F")
        "fail"
      elsif line.match?(/^\s*\*\s/) || line.strip.start_with?("*")
        "pending"
      elsif line.include?("ERROR") || line.include?("Error:")
        "error"
      else
        "info"
      end
    end

    def detect_n1_patterns(queries)
      pattern_counts = Hash.new(0)
      queries.each do |q|
        normalized = q[:sql].gsub(/\d+/, "?").gsub(/'[^']*'/, "?").strip
        pattern_counts[normalized] += 1
      end
      pattern_counts.select { |_, count| count >= 3 }
    end

    def n1_association(pattern)
      pattern.match(/FROM "?(\w+)"?/i)&.captures&.first&.singularize || "association"
    end

    def extract_coverage_pct(resultset, file_path)
      rel       = file_path.sub(Rails.root.to_s + "/", "")
      all_lines = resultset.values.flat_map { |r| r.dig("coverage", rel)&.compact }.compact
      return nil if all_lines.empty?
      covered   = all_lines.count { |v| v.to_i > 0 }
      (covered.to_f / all_lines.size * 100).round(1)
    end

    def json_output_path(run_id, file_key)
      dir = Rails.root.join("log", "devmetrics", "runs", run_id.to_s)
      FileUtils.mkdir_p(dir)
      dir.join("#{file_key}.json").to_s
    end

    def write_run_summary(run)
      results = run.file_results
      dir     = Rails.root.join("log", "devmetrics", "runs", run.run_id.to_s)
      summary = {
        run_id:       run.run_id,
        started_at:   run.started_at.iso8601,
        finished_at:  run.finished_at.iso8601,
        total_files:  run.total_files,
        total_tests:  results.sum(:total_tests),
        total_passed: results.sum(:passed_tests),
        total_failed: results.sum(:failed_tests),
        total_slow:   results.sum(:slow_query_count),
        total_n1:     results.sum(:n1_count),
        avg_coverage: (results.average(:coverage)&.round(1) || 0),
        files:        results.map { |r|
          { key: r.file_key, status: r.status, coverage: r.coverage,
            slow: r.slow_query_count, n1: r.n1_count }
        }
      }
      File.write(dir.join("_run_summary.json"), JSON.pretty_generate(summary))
    end
  end
end
