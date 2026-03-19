import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["logOutput", "runButton", "statusText"]

  connect() {
    console.log("DevMetrics Controller connected")
  }

  async runTests(event) {
    event.preventDefault()

    this.runButtonTarget.disabled = true
    this.runButtonTarget.innerHTML = `<svg class="animate-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 12a9 9 0 11-6.219-8.56"/></svg> Running...`
    this.statusTextTarget.textContent = "Executing performance suite... check terminal for progress."

    try {
      const response = await fetch("/devmetrics/run_tests", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (data.status === "finished") {
        this.logOutputTarget.textContent = data.results
        this.statusTextTarget.textContent = `Tests finished! Executed ${data.spec_count} specs.`
      } else {
        this.statusTextTarget.textContent = `Error: ${data.message || "Unknown error"}`
      }
    } catch (error) {
      console.error("Error running tests:", error)
      this.statusTextTarget.textContent = "Request failed. Check console for details."
    } finally {
      this.runButtonTarget.disabled = false
      this.runButtonTarget.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polygon points="5,3 19,12 5,21"/></svg> Run Performance Tests`
    }
  }
}
