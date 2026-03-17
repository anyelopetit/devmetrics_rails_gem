import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Connects to data-controller="metrics"
export default class extends Controller {
  static targets = [
    "totalQueries", "avgDuration", "nPlusOneCount",
    "coverage", "coverageTrend", "coverageBar", "coverageBarEl",
    "memoryUsage", "memoryBar",
    "dbConnections", "connectionBar",
    "slowQueriesList",
    // Test runner targets
    "runTestsBtn", "testPanel", "testOutput", "testStatus", "testStatusBadge",
    "testProgressBar", "testProgressText", "testFileCount"
  ]

  connect() {
    this.subscription = consumer.subscriptions.create("MetricsChannel", {
      received: this.handlePayload.bind(this)
    })
    // No more auto-polling — metrics are broadcast on-demand by the test runner
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
  }

  // ── Test Runner ──────────────────────────────────────────────────────────

  runTests(event) {
    event.preventDefault()
    if (this.isRunning) return

    this.isRunning = true
    this.setRunningState(true)

    fetch("/devmetrics/run_tests", {
      method: "POST",
      headers: { "Accept": "application/json" }
    })
    .then(r => r.json())
    .then(data => {
      if (data.status === "error") {
        this.appendTerminalLine(`⚠  ${data.message}`, "error")
        this.setRunningState(false)
        this.isRunning = false
      } else {
        this.clearTerminal()
        this.showTestPanel()
        this.appendTerminalLine(`▶  Starting performance run · ${data.spec_count} spec file(s) found…`, "info")
      }
    })
    .catch(err => {
      this.appendTerminalLine(`✗  Fetch error: ${err}`, "error")
      this.setRunningState(false)
      this.isRunning = false
    })
  }

  // ── Cable payload dispatcher ─────────────────────────────────────────────

  handlePayload(data) {
    switch (data.type) {
      case "stats_update":
        this.updateStats(data.payload)
        break
      case "new_slow_query":
        this.appendSlowQuery(data.payload)
        break
      case "test_run_started":
        this.showTestPanel()
        this.clearTerminal()
        this.updateProgress(0, 0, data.spec_count)
        this.appendTerminalLine(`▶  Run ${data.run_id} started · Parallel execution of ${data.spec_count} file(s)`, "info")
        break
      case "test_progress":
        this.updateProgress(data.progress, data.completed, data.total)
        break
      case "test_output":
        this.appendTerminalLine(data.line, data.line_type)
        break
      case "slow_query_detected":
        this.appendTerminalLine(
          `⚡  Slow query (${data.payload.duration_ms}ms): ${data.payload.sql}`,
          "warning"
        )
        break
      case "test_run_complete":
        this.updateProgress(100, data.payload.total_files || data.payload.completed_files, data.payload.total_files || data.payload.completed_files)
        this.handleRunComplete(data)
        break
      case "test_run_error":
        this.appendTerminalLine(`✗  Error: ${data.message}`, "error")
        this.setRunningState(false)
        this.isRunning = false
        break
    }
  }

  // ── Stats updater ────────────────────────────────────────────────────────

  updateStats(stats) {
    if (this.hasTotalQueriesTarget) this.totalQueriesTarget.textContent = stats.total_queries
    if (this.hasAvgDurationTarget)  this.avgDurationTarget.textContent  = stats.avg_duration

    if (this.hasNPlusOneCountTarget) {
      this.nPlusOneCountTarget.textContent  = stats.n_plus_one_count
      this.nPlusOneCountTarget.style.color  = stats.n_plus_one_count > 0 ? "#EF4444" : "#22C55E"
    }

    if (this.hasCoverageTarget)    this.coverageTarget.textContent    = `${stats.coverage}%`
    if (this.hasCoverageBarTarget) this.coverageBarTarget.textContent = `${stats.coverage}%`
    if (this.hasCoverageBarElTarget) {
      this.coverageBarElTarget.style.width = `${Math.min(stats.coverage, 100)}%`
    }

    if (this.hasMemoryUsageTarget && this.hasMemoryBarTarget) {
      this.memoryUsageTarget.textContent = `${stats.memory_mb} MB`
      this.memoryBarTarget.style.width   = `${Math.min((stats.memory_mb / 512) * 100, 100)}%`
    }

    if (this.hasDbConnectionsTarget && this.hasConnectionBarTarget) {
      this.dbConnectionsTarget.textContent = `${stats.db_connections} / 50`
      this.connectionBarTarget.style.width = `${Math.min((stats.db_connections / 50) * 100, 100)}%`
    }

    document.dispatchEvent(new CustomEvent("metrics:updated"))
  }

  appendSlowQuery(query) {
    if (!this.hasSlowQueriesListTarget) return

    const noMsgs = document.getElementById("no-slow-queries-msg")
    if (noMsgs) noMsgs.remove()

    const html = `
      <div class="slow-query-item fade-in">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:0.5rem;">
          <div style="display:flex;align-items:center;gap:0.5rem;">
            <span class="badge badge-red">N+1</span>
            <span style="font-size:0.875rem;font-weight:600;color:#FCA5A5;font-family:var(--font-mono);">${query.model_class || "Query"}</span>
          </div>
          <span style="font-size:0.7rem;color:var(--text-muted);font-family:var(--font-mono);">${query.duration}ms</span>
        </div>
        <div style="background:rgba(15,23,42,0.8);border:1px solid rgba(239,68,68,0.15);border-radius:6px;padding:0.625rem 0.75rem;">
          <code style="font-family:var(--font-mono);font-size:0.8rem;color:#A5F3FC;">${query.fix_suggestion || query.query_sql || ""}</code>
        </div>
      </div>
    `
    this.slowQueriesListTarget.insertAdjacentHTML("afterbegin", html)
    if (this.slowQueriesListTarget.children.length > 5) {
      this.slowQueriesListTarget.lastElementChild.remove()
    }
  }

  // ── Test runner UI helpers ───────────────────────────────────────────────

  updateProgress(progress, completed, total) {
    if (this.hasTestProgressBarTarget) {
      this.testProgressBarTarget.style.width = `${progress}%`
    }
    if (this.hasTestProgressTextTarget) {
      this.testProgressTextTarget.textContent = `${Math.round(progress)}% Complete`
    }
    if (this.hasTestFileCountTarget) {
      if (total > 0) {
        this.testFileCountTarget.textContent = `${completed} / ${total} files`
      } else {
        this.testFileCountTarget.textContent = ""
      }
    }
  }

  handleRunComplete(data) {
    const success = data.success
    const icon    = success ? "✓" : "✗"
    const label   = success ? "All tests passed" : "Tests completed with failures"

    this.appendTerminalLine("", "blank")
    this.appendTerminalLine(`${icon}  ${label}`, success ? "success" : "error")

    if (this.hasTestStatusBadgeTarget) {
      this.testStatusBadgeTarget.textContent  = success ? "Passed" : "Failed"
      this.testStatusBadgeTarget.style.color  = success ? "#22C55E" : "#EF4444"
    }

    this.updateStats(data.payload)
    this.setRunningState(false)
    this.isRunning = false
  }

  showTestPanel() {
    if (this.hasTestPanelTarget) {
      this.testPanelTarget.style.display = "block"
    }
  }

  clearTerminal() {
    if (this.hasTestOutputTarget) this.testOutputTarget.innerHTML = ""
  }

  appendTerminalLine(text, lineType) {
    if (!this.hasTestOutputTarget) return

    const colors = {
      error:          "#F87171",
      warning:        "#FBBF24",
      success:        "#4ADE80",
      info:           "#60A5FA",
      example_passed: "#4ADE80",
      example_failed: "#F87171",
      example_pending:"#FBBF24",
      summary:        "#C0CAE0",
      failure_header: "#F87171",
      backtrace:      "#64748B",
      blank:          "transparent",
      default:        "#94A3B8"
    }

    const color = colors[lineType] || colors.default
    const span  = document.createElement("span")
    span.style.color = color
    span.style.display = "block"
    span.style.lineHeight = "1.6"
    span.textContent = text || " "

    this.testOutputTarget.appendChild(span)
    this.testOutputTarget.scrollTop = this.testOutputTarget.scrollHeight
  }

  setRunningState(running) {
    if (this.hasRunTestsBtnTarget) {
      const btn = this.runTestsBtnTarget
      if (running) {
        btn.setAttribute("disabled", true)
        btn.style.opacity = "0.6"
        btn.style.cursor  = "not-allowed"
        btn.dataset.originalText = btn.innerHTML
        btn.innerHTML = `
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="animation:spin 1s linear infinite;">
            <path d="M21 12a9 9 0 11-6.219-8.56"/>
          </svg>
          Running…
        `
      } else {
        btn.removeAttribute("disabled")
        btn.style.opacity = "1"
        btn.style.cursor  = "pointer"
        btn.innerHTML = btn.dataset.originalText || "Run Performance Tests"
      }
    }
  }
}
