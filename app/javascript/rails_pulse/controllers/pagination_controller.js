import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["limit"]
  static values = {
    storageKey: { type: String, default: "rails_pulse_pagination_limit" },
    url: String
  }

  connect() {
    this.restorePaginationLimit()
  }

  // Update pagination limit and refresh the turbo frame
  updateLimit() {
    const limit = this.limitTarget.value

    // Save to session storage only - no server request needed
    sessionStorage.setItem(this.storageKeyValue, limit)

    // Find the closest turbo frame and reload it to apply new pagination
    const turboFrame = this.element.closest('turbo-frame')
    if (turboFrame) {
      // Add the limit as a URL parameter so server picks it up
      const currentUrl = new URL(window.location)
      currentUrl.searchParams.set('limit', limit)
      turboFrame.src = currentUrl.pathname + currentUrl.search
    } else {
      // Fallback to page reload if not within a turbo frame
      const currentUrl = new URL(window.location)
      currentUrl.searchParams.set('limit', limit)
      window.location.href = currentUrl.pathname + currentUrl.search
    }
  }

  // Get CSRF token from meta tag
  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute('content') : ''
  }

  // Save the pagination limit to session storage when it changes
  savePaginationLimit() {
    const limit = this.limitTarget.value
    sessionStorage.setItem(this.storageKeyValue, limit)
  }

  // Restore the pagination limit from session storage on page load
  restorePaginationLimit() {
    const savedLimit = sessionStorage.getItem(this.storageKeyValue)
    if (savedLimit && this.limitTarget) {
      // Only set if the current value is different (prevents unnecessary DOM updates)
      if (this.limitTarget.value !== savedLimit) {
        this.limitTarget.value = savedLimit
        // Don't trigger change event when restoring from session - prevents infinite loops
      }
    }
  }
}
