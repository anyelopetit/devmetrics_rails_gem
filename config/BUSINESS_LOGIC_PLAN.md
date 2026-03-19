# DevMetrics — Parallel Real-Time Test Runner
## Full Implementation Plan for Claude Code

---

## Overview

Replace the single sequential `PerformanceTestRunnerJob` with a **fan-out architecture**: one
background job per spec file, all running in parallel, each streaming live output to its own
panel in the browser via ActionCable. Every panel shows a live terminal, slow queries, N+1
detections, and per-file coverage as they happen.

---

## Architecture Summary

```
POST /devmetrics/run_tests
  → RunOrchestrator.call
    → Dir.glob spec/requests/**/*_spec.rb
    → creates Run record (run_id, status: :running)
    → enqueues FileRunnerJob per file (all at once)
    → broadcasts { type: "run_started", files: [...file_keys] }

FileRunnerJob (N jobs in parallel, one per file)
  → Open3.popen2e("bundle exec rspec <file> ...")
  → ActiveSupport::Notifications subscriber (scoped to job thread)
  → LogWriter appends to log/devmetrics/runs/<run_id>/<file_key>.log
  → broadcasts per-file events to "devmetrics:file:<file_key>"

Browser (Stimulus metrics_controller.js)
  → subscribes to "devmetrics:run" for run_started
  → on run_started: creates panel + subscription per file_key
  → each subscription handles: test_output, slow_query, n1_detected,
    coverage_update, file_complete
  → panels collapse/expand, progress bar, live terminal, sidebar stats
```

---

## Phase 1 — Database & Models

### Step 1.1 — Generate migrations

```bash
rails g devmetrics:install   # already exists — skip if done
```

Generate new migration inside the gem:

```bash
# From the gem root
rails g migration CreateDevmetricsRuns \
  run_id:string status:integer started_at:datetime finished_at:datetime \
  total_files:integer completed_files:integer --no-test-framework
```

```bash
rails g migration CreateDevmetricsFileResults \
  run_id:string file_key:string file_path:string status:integer \
  total_tests:integer passed_tests:integer failed_tests:integer \
  slow_query_count:integer n1_count:integer coverage:float \
  duration_ms:integer log_path:string --no-test-framework
```

### Step 1.2 — Models

**`lib/devmetrics/models/run.rb`**

```ruby
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
```

**`lib/devmetrics/models/file_result.rb`**

```ruby
module Devmetrics
  class FileResult < ActiveRecord::Base
    self.table_name = "devmetrics_file_results"

    enum :status, { pending: 0, running: 1, passed: 2, failed: 3 }

    belongs_to :run, foreign_key: :run_id, primary_key: :run_id,
               class_name: "Devmetrics::Run"

    def self.file_key_for(file_path)
      File.basename(file_path, ".rb").gsub(/[^a-z0-9_]/, "_")
    end
  end
end
```

---

## Phase 2 — Core Backend Services

### Step 2.1 — LogWriter

**`lib/devmetrics/log_writer.rb`**

```ruby
module Devmetrics
  class LogWriter
    LOG_BASE = Rails.root.join("log", "devmetrics", "runs")

    def self.open(run_id, file_key)
      dir = LOG_BASE.join(run_id.to_s)
      FileUtils.mkdir_p(dir)
      new(dir.join("#{file_key}.log"))
    end

    def initialize(path)
      @path = path
      @file = File.open(path, "w")
    end

    def write(line)
      @file.puts(line)
      @file.flush
    end

    def close
      @file.close
    end

    def path
      @path.to_s
    end
  end
end
```

### Step 2.2 — SqlInstrumentor

Scoped per-job SQL tracking using thread-local state so parallel jobs don't bleed into each other.

**`lib/devmetrics/sql_instrumentor.rb`**

```ruby
module Devmetrics
  class SqlInstrumentor
    THREAD_KEY = :devmetrics_sql_collector

    def self.around_run
      Thread.current[THREAD_KEY] = { queries: [], start: Time.current }
      yield
    ensure
      Thread.current[THREAD_KEY] = nil
    end

    def self.record(event)
      collector = Thread.current[THREAD_KEY]
      return unless collector

      ms = event.duration.round(2)
      sql = event.payload[:sql].to_s.strip

      return if sql.match?(/\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      collector[:queries] << { sql: sql, ms: ms, at: Time.current.iso8601 }
      collector[:queries].last
    end

    def self.queries
      Thread.current[THREAD_KEY]&.dig(:queries) || []
    end
  end
end
```

Register the subscriber once in the engine initializer (not per-job):

```ruby
# lib/devmetrics/engine.rb  (inside the existing Engine class)
initializer "devmetrics.sql_notifications" do
  ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    ::Devmetrics::SqlInstrumentor.record(event)
  end
end
```

### Step 2.3 — FileRunnerJob

**`lib/devmetrics/jobs/file_runner_job.rb`**

```ruby
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
          total_tests:  passed + failed
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
          run_id:   result.run_id,
          file_key: result.file_key,
          sql:      q[:sql],
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

      # SimpleCov resultset if present
      resultset_path = Rails.root.join("coverage", ".resultset.json")
      if File.exist?(resultset_path)
        rs   = JSON.parse(File.read(resultset_path)) rescue {}
        pct  = extract_coverage_pct(rs, file_path)
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

      # Increment run-level counter and check if all files done
      run = ::Devmetrics::Run.find_by(run_id: run_id)
      if run
        run.with_lock do
          run.increment!(:completed_files)
          if run.completed_files >= run.total_files
            run.update!(status: :completed, finished_at: Time.current)
            ActionCable.server.broadcast(
              "devmetrics:run:#{run_id}",
              type: "run_complete",
              run_id: run_id,
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
      rel = file_path.sub(Rails.root.to_s + "/", "")
      all_lines = resultset.values.flat_map { |r| r.dig("coverage", rel)&.compact }.compact
      return nil if all_lines.empty?
      covered = all_lines.count { |v| v.to_i > 0 }
      (covered.to_f / all_lines.size * 100).round(1)
    end

    def json_output_path(run_id, file_key)
      dir = Rails.root.join("log", "devmetrics", "runs", run_id.to_s)
      FileUtils.mkdir_p(dir)
      dir.join("#{file_key}.json").to_s
    end

    def write_run_summary(run)
      results  = run.file_results
      dir      = Rails.root.join("log", "devmetrics", "runs", run.run_id.to_s)
      summary  = {
        run_id:        run.run_id,
        started_at:    run.started_at.iso8601,
        finished_at:   run.finished_at.iso8601,
        total_files:   run.total_files,
        total_tests:   results.sum(:total_tests),
        total_passed:  results.sum(:passed_tests),
        total_failed:  results.sum(:failed_tests),
        total_slow:    results.sum(:slow_query_count),
        total_n1:      results.sum(:n1_count),
        avg_coverage:  (results.average(:coverage)&.round(1) || 0),
        files:         results.map { |r|
          { key: r.file_key, status: r.status, coverage: r.coverage,
            slow: r.slow_query_count, n1: r.n1_count }
        }
      }
      File.write(dir.join("_run_summary.json"), JSON.pretty_generate(summary))
    end
  end
end
```

### Step 2.4 — RunOrchestrator

**`lib/devmetrics/run_orchestrator.rb`**

```ruby
module Devmetrics
  class RunOrchestrator
    SPEC_GLOB = "spec/requests/**/*_spec.rb"

    def self.call
      new.call
    end

    def call
      file_paths = discover_files
      return { error: "No request specs found in #{SPEC_GLOB}" } if file_paths.empty?

      run = ::Devmetrics::Run.create_for_files(file_paths)

      file_metas = file_paths.map do |path|
        file_key = ::Devmetrics::FileResult.file_key_for(path)
        ::Devmetrics::FileResult.create!(
          run_id:    run.run_id,
          file_key:  file_key,
          file_path: path,
          status:    :pending
        )
        { file_key: file_key, file_path: path, display_name: path.sub(Rails.root.to_s + "/", "") }
      end

      ActionCable.server.broadcast(
        "devmetrics:run:#{run.run_id}",
        type:    "run_started",
        run_id:  run.run_id,
        files:   file_metas
      )

      file_metas.each do |meta|
        ::Devmetrics::FileRunnerJob.perform_later(
          run_id:    run.run_id,
          file_path: meta[:file_path],
          file_key:  meta[:file_key]
        )
      end

      { run_id: run.run_id, file_count: file_metas.size, files: file_metas }
    end

    private

    def discover_files
      all = Dir.glob(Rails.root.join(SPEC_GLOB)).sort

      # Prefer files tagged with devmetrics (require 'devmetrics' or devmetrics: true)
      tagged = all.select { |f| File.read(f).match?(/devmetrics/i) }
      tagged.any? ? tagged : all
    end
  end
end
```

---

## Phase 3 — ActionCable Channel

### Step 3.1 — Update MetricsChannel

**`app/channels/devmetrics/metrics_channel.rb`**

```ruby
module Devmetrics
  class MetricsChannel < ActionCable::Channel::Base
    def subscribed
      case params[:stream_type]
      when "run"
        run_id = params[:run_id]
        stream_from "devmetrics:run:#{run_id}" if run_id.present?
      when "file"
        file_key = params[:file_key]
        run_id   = params[:run_id]
        if file_key.present? && run_id.present?
          stream_from "devmetrics:file:#{file_key}:#{run_id}"
        end
      else
        # Legacy support — global stream
        stream_from "devmetrics:metrics"
      end
    end

    def unsubscribed
      stop_all_streams
    end
  end
end
```

---

## Phase 4 — Controller

### Step 4.1 — MetricsController#run_tests

Replace the existing `run_tests` action:

```ruby
# app/controllers/devmetrics/metrics_controller.rb

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
    run_id:    run.run_id,
    status:    run.status,
    files:     run.file_results.map { |r|
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
```

### Step 4.2 — Routes

```ruby
# In the engine's routes.rb
Devmetrics::Engine.routes.draw do
  root to: "metrics#index"

  get  "playground",                to: "metrics#playground"
  post "run_tests",                 to: "metrics#run_tests"
  post "playground",                to: "metrics#playground_execute"
  get  "runs/:run_id/status",       to: "metrics#run_status"
  get  "runs/:run_id/logs/:file_key/download", to: "metrics#download_log"

  mount ActionCable.server => "/cable"
end
```

---

## Phase 5 — Frontend (Stimulus + ActionCable)

### Step 5.1 — HTML template

**`app/views/devmetrics/metrics/index.html.erb`**

Key structure only — fill in your existing layout wrapper:

```erb
<div data-controller="metrics"
     data-metrics-cable-url-value="<%= devmetrics_mount_path %>/cable">

  <%# Header + controls %>
  <div class="dm-header">
    <h1>DevMetrics</h1>
    <button data-action="click->metrics#runTests" data-metrics-target="runBtn">
      Run performance tests
    </button>
  </div>

  <%# Summary stat cards — updated live %>
  <div class="dm-summary" data-metrics-target="summary">
    <div class="dm-stat" data-stat="totalTests">
      <div class="dm-stat-label">Tests run</div>
      <div class="dm-stat-value" data-metrics-target="statTotalTests">—</div>
    </div>
    <div class="dm-stat" data-stat="slowQueries">
      <div class="dm-stat-label">Slow queries</div>
      <div class="dm-stat-value" data-metrics-target="statSlowQueries">—</div>
    </div>
    <div class="dm-stat" data-stat="n1Issues">
      <div class="dm-stat-label">N+1 issues</div>
      <div class="dm-stat-value" data-metrics-target="statN1Issues">—</div>
    </div>
    <div class="dm-stat" data-stat="coverage">
      <div class="dm-stat-label">Avg coverage</div>
      <div class="dm-stat-value" data-metrics-target="statCoverage">—</div>
    </div>
  </div>

  <%# File panels — injected dynamically by JS %>
  <div class="dm-file-list" data-metrics-target="fileList"></div>

</div>
```

### Step 5.2 — Stimulus controller

**`app/javascript/devmetrics/controllers/metrics_controller.js`**

```javascript
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = [
    "runBtn", "fileList", "summary",
    "statTotalTests", "statSlowQueries", "statN1Issues", "statCoverage"
  ]

  static values = { cableUrl: String }

  connect() {
    this.subscriptions = {}   // file_key -> ActionCable subscription
    this.runSubscription = null
    this.stats = { tests: 0, slow: 0, n1: 0, coverageSum: 0, coverageCount: 0 }
    this.currentRunId = null
  }

  disconnect() {
    this.teardownSubscriptions()
  }

  // ── Run trigger ──────────────────────────────────────────────────────────

  async runTests() {
    this.runBtnTarget.disabled = true
    this.runBtnTarget.textContent = "Starting…"
    this.resetState()

    try {
      const resp = await fetch(this.runTestsUrl, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken, "Content-Type": "application/json" }
      })
      const data = await resp.json()
      if (!resp.ok) throw new Error(data.error || "Failed to start run")

      this.currentRunId = data.run_id
      this.subscribeToRun(data.run_id)

    } catch (err) {
      this.runBtnTarget.disabled = false
      this.runBtnTarget.textContent = "Run performance tests"
      console.error("DevMetrics run error:", err)
    }
  }

  // ── Run-level subscription ────────────────────────────────────────────────

  subscribeToRun(runId) {
    this.runSubscription = consumer.subscriptions.create(
      { channel: "Devmetrics::MetricsChannel", stream_type: "run", run_id: runId },
      {
        received: (data) => this.handleRunEvent(data)
      }
    )
  }

  handleRunEvent(data) {
    switch (data.type) {
      case "run_started":
        this.runBtnTarget.textContent = `Running (${data.files.length} files)…`
        data.files.forEach(f => {
          this.createFilePanel(f.file_key, f.display_name, data.run_id)
          this.subscribeToFile(f.file_key, data.run_id)
        })
        break

      case "run_complete":
        this.runBtnTarget.disabled = false
        this.runBtnTarget.textContent = "Run performance tests"
        this.runSubscription?.unsubscribe()
        break
    }
  }

  // ── Per-file subscription ─────────────────────────────────────────────────

  subscribeToFile(fileKey, runId) {
    const sub = consumer.subscriptions.create(
      {
        channel:     "Devmetrics::MetricsChannel",
        stream_type: "file",
        file_key:    fileKey,
        run_id:      runId
      },
      { received: (data) => this.handleFileEvent(fileKey, data) }
    )
    this.subscriptions[fileKey] = sub
  }

  handleFileEvent(fileKey, data) {
    switch (data.type) {
      case "file_started":
        this.setFileDot(fileKey, "running")
        break

      case "test_output":
        this.appendTerminalLine(fileKey, data.line, data.event_type)
        if (data.event_type === "pass" || data.event_type === "fail") {
          this.advanceProgress(fileKey)
        }
        break

      case "slow_query":
        this.appendSidebarItem(fileKey, "slow", `${data.query.ms}ms — ${data.query.sql}`)
        this.stats.slow++
        this.updateSummaryStats()
        break

      case "n1_detected":
        this.appendSidebarItem(fileKey, "n1", data.message)
        this.stats.n1++
        this.updateSummaryStats()
        break

      case "coverage_update":
        this.setCoverageLabel(fileKey, data.pct)
        this.stats.coverageSum += data.pct
        this.stats.coverageCount++
        this.updateSummaryStats()
        break

      case "file_complete":
        this.finalizePanel(fileKey, data)
        this.subscriptions[fileKey]?.unsubscribe()
        delete this.subscriptions[fileKey]
        break

      case "file_error":
        this.setFileDot(fileKey, "error")
        this.appendTerminalLine(fileKey, `ERROR: ${data.message}`, "error")
        break
    }
  }

  // ── Panel construction ────────────────────────────────────────────────────

  createFilePanel(fileKey, displayName, runId) {
    const panel = document.createElement("div")
    panel.id = `dm-file-${fileKey}`
    panel.className = "dm-file-row"
    panel.innerHTML = this.panelTemplate(fileKey, displayName, runId)
    this.fileListTarget.appendChild(panel)
    // Auto-open the first panel
    if (this.fileListTarget.children.length === 1) {
      this.togglePanel(fileKey)
    }
  }

  panelTemplate(fileKey, displayName, runId) {
    return `
      <div class="dm-file-header" data-action="click->metrics#togglePanel"
           data-file-key="${fileKey}">
        <span class="dm-chevron" id="dm-chev-${fileKey}">▶</span>
        <span class="dm-dot dm-dot--pending" id="dm-dot-${fileKey}"></span>
        <span class="dm-file-name">${displayName}</span>
        <span class="dm-file-meta" id="dm-meta-${fileKey}"></span>
      </div>

      <div class="dm-progress-bar">
        <div class="dm-progress-fill" id="dm-prog-${fileKey}" style="width: 0%"></div>
      </div>

      <div class="dm-panel" id="dm-panel-${fileKey}">
        <div class="dm-terminal" id="dm-term-${fileKey}"></div>
        <div class="dm-sidebar">
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">Slow queries</div>
            <div id="dm-slow-${fileKey}"></div>
          </div>
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">N+1 issues</div>
            <div id="dm-n1-${fileKey}"></div>
          </div>
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">Coverage</div>
            <div id="dm-cov-${fileKey}" class="dm-sidebar-cov">—</div>
          </div>
          <div class="dm-sidebar-section">
            <a href="${this.logDownloadUrl(runId, fileKey)}"
               class="dm-log-link" id="dm-log-${fileKey}" style="display:none">
              Download log
            </a>
          </div>
        </div>
      </div>
    `
  }

  togglePanel(fileKey) {
    // Called by data-action click or programmatically
    if (typeof fileKey !== "string") {
      // Called from data-action — extract from dataset
      fileKey = fileKey.currentTarget.dataset.fileKey
    }
    const panel = document.getElementById(`dm-panel-${fileKey}`)
    const chev  = document.getElementById(`dm-chev-${fileKey}`)
    const open  = panel.classList.toggle("dm-panel--open")
    chev.classList.toggle("dm-chevron--open", open)
  }

  // ── Panel update helpers ──────────────────────────────────────────────────

  appendTerminalLine(fileKey, text, eventType = "info") {
    const term = document.getElementById(`dm-term-${fileKey}`)
    if (!term) return
    const line = document.createElement("div")
    line.className = `dm-term-line dm-term-line--${eventType}`
    line.textContent = text
    term.appendChild(line)
    term.scrollTop = term.scrollHeight

    this.stats.tests += (eventType === "pass" || eventType === "fail") ? 1 : 0
    this.updateSummaryStats()
  }

  appendSidebarItem(fileKey, type, text) {
    const container = document.getElementById(`dm-${type}-${fileKey}`)
    if (!container) return
    const item = document.createElement("div")
    item.className = `dm-sidebar-item dm-sidebar-item--${type}`
    item.textContent = text
    container.appendChild(item)
  }

  advanceProgress(fileKey) {
    // Optimistic progress: each completed test line moves the bar
    // We don't know total count upfront, so we use a sqrt curve that
    // approaches 95% and snaps to 100% on file_complete
    const fill = document.getElementById(`dm-prog-${fileKey}`)
    if (!fill) return
    const current = parseFloat(fill.style.width) || 0
    const next = Math.min(95, current + (95 - current) * 0.12)
    fill.style.width = `${next.toFixed(1)}%`
  }

  setFileDot(fileKey, state) {
    const dot = document.getElementById(`dm-dot-${fileKey}`)
    if (!dot) return
    dot.className = `dm-dot dm-dot--${state}`
  }

  setCoverageLabel(fileKey, pct) {
    const el = document.getElementById(`dm-cov-${fileKey}`)
    if (el) el.textContent = `${pct}%`
  }

  finalizePanel(fileKey, data) {
    const status = data.status   // "passed" | "failed"
    this.setFileDot(fileKey, status)

    const fill = document.getElementById(`dm-prog-${fileKey}`)
    if (fill) {
      fill.style.width = "100%"
      fill.classList.toggle("dm-progress-fill--passed", status === "passed")
      fill.classList.toggle("dm-progress-fill--failed", status === "failed")
    }

    const meta = document.getElementById(`dm-meta-${fileKey}`)
    if (meta) {
      meta.innerHTML = this.metaBadges(data)
    }

    const logLink = document.getElementById(`dm-log-${fileKey}`)
    if (logLink) logLink.style.display = "block"
  }

  metaBadges(data) {
    const secs = ((data.duration_ms || 0) / 1000).toFixed(2)
    let html = `<span class="dm-badge dm-badge--time">${secs}s</span>`
    if (data.n1_count > 0) html += `<span class="dm-badge dm-badge--n1">${data.n1_count} N+1</span>`
    if (data.slow_count > 0) html += `<span class="dm-badge dm-badge--slow">${data.slow_count} slow</span>`
    if (data.coverage != null) html += `<span class="dm-badge dm-badge--cov">${data.coverage}% cov</span>`
    return html
  }

  // ── Summary stats ─────────────────────────────────────────────────────────

  updateSummaryStats() {
    if (this.hasStatTotalTestsTarget)
      this.statTotalTestsTarget.textContent = this.stats.tests

    if (this.hasStatSlowQueriesTarget)
      this.statSlowQueriesTarget.textContent = this.stats.slow

    if (this.hasStatN1IssuesTarget)
      this.statN1IssuesTarget.textContent = this.stats.n1

    if (this.hasStatCoverageTarget && this.stats.coverageCount > 0) {
      const avg = (this.stats.coverageSum / this.stats.coverageCount).toFixed(1)
      this.statCoverageTarget.textContent = `${avg}%`
    }
  }

  // ── Teardown & utilities ──────────────────────────────────────────────────

  resetState() {
    this.teardownSubscriptions()
    this.stats = { tests: 0, slow: 0, n1: 0, coverageSum: 0, coverageCount: 0 }
    this.fileListTarget.innerHTML = ""
    this.updateSummaryStats()
  }

  teardownSubscriptions() {
    Object.values(this.subscriptions).forEach(sub => sub?.unsubscribe())
    this.subscriptions = {}
    this.runSubscription?.unsubscribe()
    this.runSubscription = null
  }

  get runTestsUrl() {
    return `${window.location.origin}${this.element.closest("[data-devmetrics-mount]")
      ?.dataset.devmetricsMountPath || "/devmetrics"}/run_tests`
  }

  logDownloadUrl(runId, fileKey) {
    return `/devmetrics/runs/${runId}/logs/${fileKey}/download`
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
```

### Step 5.3 — ActionCable consumer

**`app/javascript/devmetrics/channels/consumer.js`**

```javascript
import { createConsumer } from "@rails/actioncable"
export default createConsumer()
```

---

## Phase 6 — CSS

**`app/assets/stylesheets/devmetrics/dashboard.css`**

Minimal additions on top of your existing styles:

```css
/* File list */
.dm-file-row {
  border-top: 1px solid #e5e7eb;
}

.dm-file-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 16px;
  cursor: pointer;
  user-select: none;
}

.dm-file-header:hover {
  background: #f9fafb;
}

/* Status dots */
.dm-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.dm-dot--pending { background: #d1d5db; }
.dm-dot--running { background: #f59e0b; animation: dm-pulse 1s infinite; }
.dm-dot--passed  { background: #10b981; }
.dm-dot--failed  { background: #ef4444; }
.dm-dot--error   { background: #ef4444; }

@keyframes dm-pulse {
  0%, 100% { opacity: 1; }
  50%       { opacity: 0.3; }
}

/* Chevron */
.dm-chevron { font-size: 11px; color: #9ca3af; transition: transform 0.15s; }
.dm-chevron--open { transform: rotate(90deg); }

/* Progress bar */
.dm-progress-bar {
  height: 2px;
  background: #f3f4f6;
}
.dm-progress-fill {
  height: 100%;
  background: #f59e0b;
  transition: width 0.25s ease-out;
}
.dm-progress-fill--passed { background: #10b981; }
.dm-progress-fill--failed { background: #ef4444; }

/* Panel (collapsed by default) */
.dm-panel {
  display: none;
  border-top: 1px solid #e5e7eb;
}
.dm-panel--open {
  display: flex;
}

/* Terminal pane */
.dm-terminal {
  flex: 1;
  font-family: "SF Mono", "Fira Code", monospace;
  font-size: 11px;
  line-height: 1.65;
  padding: 10px 14px;
  max-height: 240px;
  overflow-y: auto;
  background: #0f172a;
  color: #94a3b8;
}
.dm-term-line--pass    { color: #34d399; }
.dm-term-line--fail    { color: #f87171; }
.dm-term-line--error   { color: #f87171; }
.dm-term-line--pending { color: #fbbf24; }
.dm-term-line--summary { color: #e2e8f0; font-weight: 600; }

/* Sidebar */
.dm-sidebar {
  width: 220px;
  border-left: 1px solid #1e293b;
  background: #0f172a;
  padding: 10px 12px;
  font-size: 11px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.dm-sidebar-label {
  color: #475569;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin-bottom: 4px;
}
.dm-sidebar-item {
  color: #94a3b8;
  padding: 2px 0;
  line-height: 1.5;
  word-break: break-word;
}
.dm-sidebar-item--slow { color: #fbbf24; }
.dm-sidebar-item--n1   { color: #f87171; }
.dm-sidebar-cov        { color: #34d399; font-size: 14px; font-weight: 600; }

.dm-log-link {
  color: #60a5fa;
  font-size: 11px;
  text-decoration: none;
}
.dm-log-link:hover { text-decoration: underline; }

/* Badges */
.dm-badge {
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 10px;
  margin-left: 4px;
}
.dm-badge--time { background: #f3f4f6; color: #6b7280; }
.dm-badge--n1   { background: #fee2e2; color: #dc2626; }
.dm-badge--slow { background: #fef3c7; color: #d97706; }
.dm-badge--cov  { background: #d1fae5; color: #065f46; }
```

---

## Phase 7 — Solid Cable & Queue Config

### Step 7.1 — Solid Cable (already installed if following README)

Ensure `config/cable.yml`:

```yaml
development:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day

production:
  adapter: solid_cable
  polling_interval: 0.5.seconds
  message_retention: 1.week
```

### Step 7.2 — ActiveJob concurrency for parallel jobs

For Solid Queue (Rails 8 / recommended):

```yaml
# config/queue.yml  (Solid Queue)
default: &default
  workers:
    - queues: [devmetrics]
      threads: 10       # allow up to 10 parallel file jobs
      processes: 1

development:
  <<: *default

production:
  <<: *default
```

For Sidekiq, add to `config/sidekiq.yml`:

```yaml
:queues:
  - [devmetrics, 5]
:concurrency: 10
```

---

## Phase 8 — Generator Updates

Update `lib/devmetrics/generators/install_generator.rb` to also:

1. Copy the two new migrations
2. Add `require "devmetrics/models/run"` and `require "devmetrics/models/file_result"` to the engine autoload
3. Print post-install notice about queue concurrency requirement

---

## File Checklist

| File | Action |
|------|--------|
| `db/migrate/..._create_devmetrics_runs.rb` | Create |
| `db/migrate/..._create_devmetrics_file_results.rb` | Create |
| `lib/devmetrics/models/run.rb` | Create |
| `lib/devmetrics/models/file_result.rb` | Create |
| `lib/devmetrics/log_writer.rb` | Create |
| `lib/devmetrics/sql_instrumentor.rb` | Create (replace inline subscriber) |
| `lib/devmetrics/run_orchestrator.rb` | Create |
| `lib/devmetrics/jobs/file_runner_job.rb` | Create (replaces `performance_test_runner_job.rb`) |
| `lib/devmetrics/engine.rb` | Modify — move SQL subscriber here, add model autoloads |
| `app/channels/devmetrics/metrics_channel.rb` | Modify — add stream_type routing |
| `app/controllers/devmetrics/metrics_controller.rb` | Modify — update `run_tests`, add `run_status`, `download_log` |
| `config/routes.rb` (engine) | Modify — add new routes |
| `app/views/devmetrics/metrics/index.html.erb` | Modify — add data targets |
| `app/javascript/devmetrics/controllers/metrics_controller.js` | Rewrite |
| `app/javascript/devmetrics/channels/consumer.js` | Create |
| `app/assets/stylesheets/devmetrics/dashboard.css` | Modify — add panel/terminal/sidebar styles |

---

## Implementation Order for Claude Code

Run these phases in sequence. Each phase is independently testable.

1. **Phase 1** — migrations + models → `rails db:migrate` → verify tables exist
2. **Phase 2** — `LogWriter`, `SqlInstrumentor`, `RunOrchestrator`, `FileRunnerJob` → unit test each class
3. **Phase 3** — `MetricsChannel` update → test via `rails console`: `ActionCable.server.broadcast(...)`
4. **Phase 4** — controller + routes → `curl -X POST /devmetrics/run_tests` → verify JSON response + job enqueued
5. **Phase 5** — Stimulus controller + consumer.js → open `/devmetrics`, run tests, watch panels appear
6. **Phase 6** — CSS → visual polish
7. **Phase 7** — queue concurrency config → verify multiple jobs actually run in parallel (`bin/jobs` or Sidekiq UI)
8. **Phase 8** — generator updates → test fresh install on a blank Rails app

---

## Testing

```bash
# Unit tests
bundle exec rspec spec/lib/devmetrics/run_orchestrator_spec.rb
bundle exec rspec spec/lib/devmetrics/jobs/file_runner_job_spec.rb
bundle exec rspec spec/lib/devmetrics/sql_instrumentor_spec.rb

# Integration: start server + run via curl
bin/dev &
curl -s -X POST http://localhost:3000/devmetrics/run_tests \
  -H "Content-Type: application/json" | jq .

# Check logs were written
ls -la log/devmetrics/runs/

# Check DB records
rails runner "puts ::Devmetrics::Run.last.inspect"
rails runner "puts ::Devmetrics::FileResult.all.map(&:status).inspect"
```

---

## Known Gotchas

**Thread isolation for SQL**: `Thread.current[THREAD_KEY]` works correctly with Puma and Solid Queue (each job runs in its own thread). With Falcon (fiber-based), replace with a Fiber-local key using `Fiber[:devmetrics_sql_collector]`.

**SimpleCov interference**: If the host app already runs SimpleCov, calling it inside a subprocess is fine — subprocesses have isolated Ruby state. The host app's coverage is unaffected.

**Open3 + bundler**: Always run `bundle exec rspec` inside `chdir: Rails.root` so the gem's own Gemfile doesn't shadow the host app's.

**Progress bar**: Because we don't know total test count before the run, the progress bar uses an asymptotic curve (each step covers 12% of remaining distance, capping at 95%). It snaps to 100% on `file_complete`. If you want an accurate bar, add `--dry-run` before the real run to get the count, but this doubles wall time.

**Log rotation**: `log/devmetrics/runs/` is not cleaned up automatically. Add a rake task `devmetrics:clean_logs[days=7]` (not in scope of this plan) or rely on `logrotate`.
