import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["limit"]
  static values = {
    storageKey: { type: String, default: "rails_pulse_pagination_limit" }
  }

  connect() {
    this.restorePaginationLimit()
  }

  // Update pagination limit and navigate to page 1 with new limit
  updateLimit() {
    const limit = this.limitTarget.value

    // Save to session storage for persistence
    sessionStorage.setItem(this.storageKeyValue, limit)

    // Build URL with limit parameter and reset to page 1
    const currentUrl = new URL(window.location)
    currentUrl.searchParams.set('limit', limit)
    currentUrl.searchParams.delete('page')

    // Use Turbo.visit for smooth navigation that preserves query params
    if (typeof Turbo !== 'undefined') {
      Turbo.visit(currentUrl.toString(), { action: 'replace' })
    } else {
      window.location.href = currentUrl.toString()
    }
  }

  // Restore the pagination limit from URL or session storage on page load
  restorePaginationLimit() {
    // URL params take precedence over session storage
    const urlParams = new URLSearchParams(window.location.search)
    const urlLimit = urlParams.get('limit')

    if (urlLimit && this.limitTarget) {
      // Sync sessionStorage with URL param
      sessionStorage.setItem(this.storageKeyValue, urlLimit)
      if (this.limitTarget.value !== urlLimit) {
        this.limitTarget.value = urlLimit
      }
    } else {
      // Fall back to sessionStorage if no URL param
      const savedLimit = sessionStorage.getItem(this.storageKeyValue)
      if (savedLimit && this.limitTarget && this.limitTarget.value !== savedLimit) {
        this.limitTarget.value = savedLimit
      }
    }
  }
}