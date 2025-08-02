import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "cancel" ]

  initialize() {
    // Simple debounce implementation for asset independence
    this.search = this.debounce(this.search.bind(this), 500)
  }

  // Simple debounce implementation (replaces lodash dependency)
  debounce(func, wait) {
    let timeout
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout)
        func(...args)
      }
      clearTimeout(timeout)
      timeout = setTimeout(later, wait)
    }
  }

  submit() {
    this.element.requestSubmit()
  }

  search() {
    this.element.requestSubmit()
  }

  cancel() {
    this.cancelTarget?.click()
  }

  preventAttachment(event) {
    event.preventDefault()
  }
}
