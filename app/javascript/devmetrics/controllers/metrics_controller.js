import { Controller } from "@hotwired/stimulus"
import consumer from "devmetrics/channels/consumer"

export default class extends Controller {
  static targets = [
    "runBtn", "fileList", "summary",
    "statTotalTests", "statSlowQueries", "statN1Issues", "statCoverage"
  ]

  static values = { cableUrl: String }

  connect() {
    this.subscriptions = {}
    this.runSubscription = null
    this.stats = { tests: 0, slow: 0, n1: 0, coverageSum: 0, coverageCount: 0 }
    this.currentRunId = null
  }

  disconnect() {
    this.teardownSubscriptions()
  }

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

      // Subscribe to run-level channel first (for run_complete), then
      // create panels and per-file subscriptions immediately from the HTTP
      // response — don't wait for run_started which fires before we subscribe.
      this.subscribeToRun(data.run_id)
      data.files.forEach(f => {
        this.createFilePanel(f.file_key, f.display_name, data.run_id)
        this.subscribeToFile(f.file_key, data.run_id)
      })

    } catch (err) {
      this.runBtnTarget.disabled = false
      this.runBtnTarget.textContent = "Run performance tests"
      console.error("DevMetrics run error:", err)
    }
  }

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

  createFilePanel(fileKey, displayName, runId) {
    const panel = document.createElement("div")
    panel.id = `dm-file-${fileKey}`
    panel.className = "dm-file-row"
    panel.innerHTML = this.panelTemplate(fileKey, displayName, runId)
    this.fileListTarget.appendChild(panel)
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
    if (typeof fileKey !== "string") {
      fileKey = fileKey.currentTarget.dataset.fileKey
    }
    const panel = document.getElementById(`dm-panel-${fileKey}`)
    const chev  = document.getElementById(`dm-chev-${fileKey}`)
    const open  = panel.classList.toggle("dm-panel--open")
    chev.classList.toggle("dm-chevron--open", open)
  }

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
    const status = data.status
    this.setFileDot(fileKey, status)

    const fill = document.getElementById(`dm-prog-${fileKey}`)
    if (fill) {
      fill.style.width = "100%"
      fill.classList.toggle("dm-progress-fill--passed", status === "passed")
      fill.classList.toggle("dm-progress-fill--failed", status === "failed")
    }

    const meta = document.getElementById(`dm-meta-${fileKey}`)
    if (meta) meta.innerHTML = this.metaBadges(data)

    const logLink = document.getElementById(`dm-log-${fileKey}`)
    if (logLink) logLink.style.display = "block"
  }

  metaBadges(data) {
    const secs = ((data.duration_ms || 0) / 1000).toFixed(2)
    let html = `<span class="dm-badge dm-badge--time">${secs}s</span>`
    if (data.n1_count > 0)   html += `<span class="dm-badge dm-badge--n1">${data.n1_count} N+1</span>`
    if (data.slow_count > 0) html += `<span class="dm-badge dm-badge--slow">${data.slow_count} slow</span>`
    if (data.coverage != null) html += `<span class="dm-badge dm-badge--cov">${data.coverage}% cov</span>`
    return html
  }

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
