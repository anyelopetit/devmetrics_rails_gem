import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["code", "output", "runBtn"]

  connect() {
    console.log("Playground controller connected")
  }

  async run() {
    if (!this.hasRunBtnTarget) return
    this.runBtnTarget.disabled = true

    try {
      const resp = await fetch("/devmetrics/playground/run", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ code: this.hasCodeTarget ? this.codeTarget.value : "" })
      })
      const data = await resp.json()
      if (this.hasOutputTarget) {
        this.outputTarget.textContent = JSON.stringify(data, null, 2)
      }
    } catch (err) {
      console.error("Playground error:", err)
    } finally {
      if (this.hasRunBtnTarget) this.runBtnTarget.disabled = false
    }
  }
}
