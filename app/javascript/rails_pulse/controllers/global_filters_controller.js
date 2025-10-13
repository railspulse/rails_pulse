import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "dateRange", "indicator"]
  static values = {
    storageKey: { type: String, default: "rails_pulse_global_filters" }
  }

  connect() {
    this.updateIndicator()
    // Don't auto-apply filters - let the user manually apply them
    // this.applyGlobalFiltersToUrl()
  }

  // Apply global filters to current URL if they exist and aren't already present
  applyGlobalFiltersToUrl() {
    const filters = this.loadFilters()
    if (!filters) return

    const url = new URL(window.location.href)
    const hasGlobalParams = url.searchParams.has('global_start_time') || url.searchParams.has('global_end_time')
    const hasPageFilters = url.searchParams.has('q')

    // Only apply global filters if:
    // 1. They exist in localStorage
    // 2. They're not already in the URL
    // 3. There are no page-specific filters (q param)
    if (!hasGlobalParams && !hasPageFilters) {
      let needsRedirect = false

      if (filters.start_time) {
        url.searchParams.set('global_start_time', filters.start_time)
        needsRedirect = true
      }

      if (filters.end_time) {
        url.searchParams.set('global_end_time', filters.end_time)
        needsRedirect = true
      }

      // Only redirect if we actually added params
      if (needsRedirect) {
        window.location.href = url.toString()
      }
    }
  }

  // Open the global filters dialog
  open(event) {
    event.preventDefault()

    // Load current filters from localStorage and populate form
    const filters = this.loadFilters()
    if (filters && filters.start_time && filters.end_time) {
      // Set the date range value for flatpickr
      // Format: "start_date to end_date"
      this.dateRangeTarget.value = `${filters.start_time} to ${filters.end_time}`
    }

    this.dialogTarget.showModal()
  }

  // Close the dialog
  close() {
    this.dialogTarget.close()
  }

  // Close dialog when clicking outside
  closeOnClickOutside({ target }) {
    target.nodeName === "DIALOG" && this.close()
  }

  // Apply filters: save to localStorage and navigate with params
  apply(event) {
    event.preventDefault()

    const dateRangeValue = this.dateRangeTarget.value

    // Validate that the date range is set
    if (!dateRangeValue || !dateRangeValue.includes(' to ')) {
      alert("Please select a date range")
      return
    }

    // Parse the date range (format: "start_date to end_date")
    const [startTime, endTime] = dateRangeValue.split(' to ').map(d => d.trim())

    // Save to localStorage
    this.saveFilters({ start_time: startTime, end_time: endTime })

    // Close dialog
    this.close()

    // Build URL with global filter params
    const url = new URL(window.location.href)

    url.searchParams.set('global_start_time', startTime)
    url.searchParams.set('global_end_time', endTime)

    // Navigate to new URL
    window.location.href = url.toString()
  }

  // Clear filters: remove from localStorage and navigate without params
  clear(event) {
    event.preventDefault()

    // Clear localStorage
    localStorage.removeItem(this.storageKeyValue)

    // Clear form input
    this.dateRangeTarget.value = ""

    // Close dialog
    this.close()

    // Remove global filter params from URL
    const url = new URL(window.location.href)
    url.searchParams.delete('global_start_time')
    url.searchParams.delete('global_end_time')

    // Navigate to clean URL
    window.location.href = url.toString()
  }

  // Load filters from localStorage
  loadFilters() {
    try {
      const stored = localStorage.getItem(this.storageKeyValue)
      return stored ? JSON.parse(stored) : null
    } catch (e) {
      console.error("Failed to load global filters from localStorage:", e)
      return null
    }
  }

  // Save filters to localStorage
  saveFilters(filters) {
    try {
      localStorage.setItem(this.storageKeyValue, JSON.stringify(filters))
      this.updateIndicator()
    } catch (e) {
      console.error("Failed to save global filters to localStorage:", e)
    }
  }

  // Check if filters are currently active
  hasActiveFilters() {
    const filters = this.loadFilters()
    return filters && (filters.start_time || filters.end_time)
  }

  // Update visual indicator to show if filters are active
  updateIndicator() {
    if (this.hasIndicatorTarget) {
      if (this.hasActiveFilters()) {
        this.indicatorTarget.classList.add("global-filters-active")
      } else {
        this.indicatorTarget.classList.remove("global-filters-active")
      }
    }
  }

  // Get current filters (for use by other controllers)
  static getGlobalFilters() {
    try {
      const stored = localStorage.getItem("rails_pulse_global_filters")
      return stored ? JSON.parse(stored) : null
    } catch (e) {
      console.error("Failed to load global filters:", e)
      return null
    }
  }
}
