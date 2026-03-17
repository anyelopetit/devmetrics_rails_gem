import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submitBtn", "spinner", "resultContainer", "durationStat", "statusStat", "output"]

  execute(event) {
    event.preventDefault()

    const query = this.inputTarget.value.trim()
    if (!query) return

    // Show loading state
    this.submitBtnTarget.classList.add('hidden')
    this.spinnerTarget.classList.remove('hidden')
    this.resultContainerTarget.classList.add('hidden')

    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch('/playground/run', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: JSON.stringify({ query: query })
    })
    .then(response => response.json())
    .then(data => {
      this.showResults(data)
    })
    .catch(error => {
      this.showResults({
        status: 'error',
        duration: 0,
        output: error.toString()
      })
    })
    .finally(() => {
      this.submitBtnTarget.classList.remove('hidden')
      this.spinnerTarget.classList.add('hidden')
    })
  }

  showResults(data) {
    this.resultContainerTarget.classList.remove('hidden')

    this.durationStatTarget.textContent = `${data.duration} ms`

    if (data.status === 'success') {
      this.statusStatTarget.textContent = 'Success'
      this.statusStatTarget.className = 'mt-1 text-lg font-medium text-green-600'
      this.outputTarget.className = 'text-sm text-green-400 font-mono whitespace-pre-wrap'
    } else {
      this.statusStatTarget.textContent = 'Error'
      this.statusStatTarget.className = 'mt-1 text-lg font-medium text-red-600'
      this.outputTarget.className = 'text-sm text-red-400 font-mono whitespace-pre-wrap'
    }

    this.outputTarget.textContent = typeof data.output === 'string' ? data.output : JSON.stringify(data.output, null, 2)
  }
}
