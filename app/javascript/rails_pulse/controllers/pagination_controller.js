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

  // Update pagination limit via AJAX and reload the page to reflect changes
  async updateLimit() {
    const limit = this.limitTarget.value

    // Save to session storage
    sessionStorage.setItem(this.storageKeyValue, limit)

    try {
      // Send AJAX request to update server session using Rails.ajax
      const response = await fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ limit: limit })
      })

      if (response.ok) {
        // Reload the page to reflect the new pagination limit
        // This preserves all current URL parameters including Ransack search params
        window.location.reload()
      } else {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
    } catch (error) {
      console.error('Error updating pagination limit:', error)
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

        // Trigger a change event to ensure any other listeners are notified
        this.limitTarget.dispatchEvent(new Event('change', { bubbles: true }))
      }
    }
  }
}
