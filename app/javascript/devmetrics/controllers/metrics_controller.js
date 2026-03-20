import { Controller } from "@hotwired/stimulus"
import consumer from "devmetrics/channels/consumer"

export default class extends Controller {
  static targets = [
    "runBtn", "fileList",
    "statTotalTests", "statSlowQueries", "statN1Issues", "statCoverage"
  ]

  static values = { cableUrl: String }

  connect() {
    this.subscriptions = {}
    this.runSubscription = null
    this.fileMeta       = {}
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
      this.runBtnTarget.textContent = `Running (${data.files.length} files)…`

      this.subscribeToRun(data.run_id)
      data.files.forEach(f => {
        this.fileMeta[f.file_key] = f
        this.createFilePanel(f.file_key, f.display_name, data.run_id)
        this.subscribeToFile(f.file_key, data.run_id)
      })

    } catch (err) {
      this.runBtnTarget.disabled = false
      this.runBtnTarget.textContent = "Run performance tests"
      console.error("DevMetrics run error:", err)
    }
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  subscribeToRun(runId) {
    this.runSubscription = consumer.subscriptions.create(
      { channel: "Devmetrics::MetricsChannel", stream_type: "run", run_id: runId },
      { received: (data) => this.handleRunEvent(data) }
    )
  }

  handleRunEvent(data) {
    if (data.type === "run_complete") {
      this.runBtnTarget.disabled = false
      this.runBtnTarget.textContent = "Run performance tests"
      this.runSubscription?.unsubscribe()
    }
  }

  subscribeToFile(fileKey, runId) {
    const sub = consumer.subscriptions.create(
      { channel: "Devmetrics::MetricsChannel", stream_type: "file", file_key: fileKey, run_id: runId },
      { received: (data) => this.handleFileEvent(fileKey, data) }
    )
    this.subscriptions[fileKey] = sub
  }

  handleFileEvent(fileKey, data) {
    switch (data.type) {

      case "file_started": {
        this.setFileDot(fileKey, "running")
        const meta = this.fileMeta[fileKey]
        const path = meta?.display_name || fileKey
        this.appendTerminalLine(fileKey, `$ bundle exec rspec ${path} --format documentation`, "command")
        break
      }

      case "test_output":
        this.appendTerminalLine(fileKey, data.line, data.event_type)
        if (data.event_type === "pass" || data.event_type === "fail") this.advanceProgress(fileKey)
        break

      case "slow_query": {
        const text = `${data.query.sql} (${data.query.ms}ms)`
        this.appendTerminalLine(fileKey, `SLOW: ${text}`, "slow")
        this.appendSidebarItem(fileKey, "slow", text)
        this.stats.slow++
        this.updateSummaryStats()
        break
      }

      case "n1_detected":
        this.appendTerminalLine(fileKey, `N+1 detected: ${data.message}`, "n1")
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
    const row = document.createElement("div")
    row.id = `dm-file-${fileKey}`
    row.className = "dm-file-row"
    row.innerHTML = this.panelTemplate(fileKey, displayName, runId)
    this.fileListTarget.appendChild(row)
    // Auto-open the first panel
    if (this.fileListTarget.children.length === 1) this.togglePanel(fileKey)
  }

  panelTemplate(fileKey, displayName, runId) {
    return `
      <div class="dm-file-header" data-action="click->metrics#togglePanel" data-file-key="${fileKey}">
        <span class="dm-chevron" id="dm-chev-${fileKey}">▶</span>
        <span class="dm-dot dm-dot--pending" id="dm-dot-${fileKey}"></span>
        <span class="dm-file-name">${displayName}</span>
        <span class="dm-file-meta" id="dm-meta-${fileKey}"></span>
      </div>

      <div class="dm-progress-bar">
        <div class="dm-progress-fill" id="dm-prog-${fileKey}" style="width:0%"></div>
      </div>

      <div class="dm-panel" id="dm-panel-${fileKey}">
        <div class="dm-terminal" id="dm-term-${fileKey}"></div>
        <div class="dm-sidebar">
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">Slow Queries</div>
            <div id="dm-slow-${fileKey}" class="dm-sidebar-items"></div>
          </div>
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">N+1 Issues</div>
            <div id="dm-n1-${fileKey}" class="dm-sidebar-items"></div>
          </div>
          <div class="dm-sidebar-section">
            <div class="dm-sidebar-label">Coverage</div>
            <div id="dm-cov-${fileKey}" class="dm-sidebar-cov">—</div>
          </div>
          <div class="dm-sidebar-section dm-sidebar-log">
            <a href="${this.logDownloadUrl(runId, fileKey)}" class="dm-log-link" id="dm-log-${fileKey}" style="display:none">
              ↓ Download log
            </a>
          </div>
        </div>
      </div>
    `
  }

  togglePanel(fileKey) {
    if (typeof fileKey !== "string") fileKey = fileKey.currentTarget.dataset.fileKey
    const panel = document.getElementById(`dm-panel-${fileKey}`)
    const chev  = document.getElementById(`dm-chev-${fileKey}`)
    const open  = panel.classList.toggle("dm-panel--open")
    chev.classList.toggle("dm-chevron--open", open)
  }

  // ── Terminal helpers ──────────────────────────────────────────────────────

  appendTerminalLine(fileKey, rawText, eventType = "info") {
    const term = document.getElementById(`dm-term-${fileKey}`)
    if (!term) return

    // Skip blank info lines that just add noise
    if (eventType === "info" && rawText.trim() === "") return

    const text = this.formatLine(rawText, eventType)
    const line = document.createElement("div")
    line.className = `dm-term-line dm-term-line--${eventType}`
    line.textContent = text
    term.appendChild(line)
    term.scrollTop = term.scrollHeight

    this.stats.tests += (eventType === "pass" || eventType === "fail") ? 1 : 0
    this.updateSummaryStats()
  }

  formatLine(text, eventType) {
    if (eventType === "pass") return "✓ " + text.replace(/^\s*[\.·✓]\s*/, "").trim()
    if (eventType === "fail") return "✗ " + text.replace(/^\s*[\.·✗]\s*/, "").trim()
    return text
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
    const fill = document.getElementById(`dm-prog-${fileKey}`)
    if (!fill) return
    const cur = parseFloat(fill.style.width) || 0
    fill.style.width = `${Math.min(95, cur + (95 - cur) * 0.12).toFixed(1)}%`
  }

  setFileDot(fileKey, state) {
    const dot = document.getElementById(`dm-dot-${fileKey}`)
    if (dot) dot.className = `dm-dot dm-dot--${state}`
  }

  setCoverageLabel(fileKey, pct) {
    const el = document.getElementById(`dm-cov-${fileKey}`)
    if (el) el.textContent = `${pct}%`
  }

  finalizePanel(fileKey, data) {
    const status = data.status
    this.setFileDot(fileKey, status)

    // Progress bar → 100%
    const fill = document.getElementById(`dm-prog-${fileKey}`)
    if (fill) {
      fill.style.width = "100%"
      fill.classList.toggle("dm-progress-fill--passed", status === "passed")
      fill.classList.toggle("dm-progress-fill--failed", status === "failed")
    }

    // Summary line in terminal
    const term = document.getElementById(`dm-term-${fileKey}`)
    if (term) {
      const sep = document.createElement("div")
      sep.className = "dm-term-separator"
      term.appendChild(sep)
      const total = (data.passed || 0) + (data.failed || 0)
      const covStr = data.coverage != null ? ` — coverage ${data.coverage}%` : ""
      this.appendTerminalLine(
        fileKey,
        `${total} example${total !== 1 ? "s" : ""}. ${data.failed || 0} failure${data.failed !== 1 ? "s" : ""}${covStr}`,
        "summary"
      )
    }

    // Header badges
    const meta = document.getElementById(`dm-meta-${fileKey}`)
    if (meta) meta.innerHTML = this.metaBadges(data)

    // Log link
    const logLink = document.getElementById(`dm-log-${fileKey}`)
    if (logLink) logLink.style.display = "inline-flex"
  }

  metaBadges(data) {
    const secs = ((data.duration_ms || 0) / 1000).toFixed(2)
    let html = `<span class="dm-badge dm-badge--time">${secs}s</span>`
    if ((data.n1_count || 0) > 0)
      html += `<span class="dm-badge dm-badge--n1">${data.n1_count} N+1</span>`
    if ((data.slow_count || 0) > 0)
      html += `<span class="dm-badge dm-badge--slow">${data.slow_count} slow</span>`
    if (data.coverage != null)
      html += `<span class="dm-badge dm-badge--cov">${data.coverage}% cov</span>`
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
    if (this.hasStatCoverageTarget && this.stats.coverageCount > 0)
      this.statCoverageTarget.textContent =
        `${(this.stats.coverageSum / this.stats.coverageCount).toFixed(1)}%`
  }

  // ── Teardown & utilities ──────────────────────────────────────────────────

  resetState() {
    this.teardownSubscriptions()
    this.fileMeta = {}
    this.stats = { tests: 0, slow: 0, n1: 0, coverageSum: 0, coverageCount: 0 }
    this.fileListTarget.innerHTML = ""
    this.updateSummaryStats()
  }

  teardownSubscriptions() {
    Object.values(this.subscriptions).forEach(s => s?.unsubscribe())
    this.subscriptions = {}
    this.runSubscription?.unsubscribe()
    this.runSubscription = null
  }

  get runTestsUrl() {
    const mount = this.element.closest("[data-devmetrics-mount-path]")
      ?.dataset.devmetricsMountPath || "/devmetrics"
    return `${mount}/run_tests`
  }

  logDownloadUrl(runId, fileKey) {
    return `/devmetrics/runs/${runId}/logs/${fileKey}/download`
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
