import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["wrapper", "dialog", "dateRange", "indicator", "form"]
  static values = {
    active: { type: Boolean, default: false }
  }

  connect() {
    this.updateIndicator()
  }

  // Open the global filters dialog
  open(event) {
    event.preventDefault()

    // If there's a value in the date range input, make sure flatpickr knows about it
    if (this.dateRangeTarget.value) {
      const datepickerController = this.application.getControllerForElementAndIdentifier(
        this.dateRangeTarget,
        'rails-pulse--datepicker'
      )

      if (datepickerController && datepickerController.flatpickr) {
        const value = this.dateRangeTarget.value
        // Parse the "start to end" format
        if (value.includes(' to ')) {
          const [start, end] = value.split(' to ').map(d => d.trim())
          // Set the dates in flatpickr
          datepickerController.flatpickr.setDate([start, end], false)
        }
      }
    }

    this.wrapperTarget.style.display = 'flex'
    // Prevent body scroll when dialog is open
    document.body.style.overflow = 'hidden'
  }

  // Close the dialog
  close(event) {
    if (event) {
      event.preventDefault()
    }
    this.wrapperTarget.style.display = 'none'
    // Restore body scroll
    document.body.style.overflow = ''
  }

  // Close dialog when clicking outside
  closeOnClickOutside(event) {
    if (event.target === this.wrapperTarget) {
      this.close(event)
    }
  }

  // Handle form submission - parse date range and add individual params
  submit(event) {
    // If clear button was clicked, let it through as-is
    if (event.submitter && event.submitter.name === "clear") {
      return
    }

    const dateRangeValue = this.dateRangeTarget.value
    const form = event.target

    // Parse date range if provided
    if (dateRangeValue && dateRangeValue.includes(' to ')) {
      const [startTime, endTime] = dateRangeValue.split(' to ').map(d => d.trim())

      // Remove any existing hidden inputs
      form.querySelectorAll('input[name="start_time"], input[name="end_time"]').forEach(el => el.remove())

      // Add new hidden inputs
      const startInput = document.createElement('input')
      startInput.type = 'hidden'
      startInput.name = 'start_time'
      startInput.value = startTime
      form.appendChild(startInput)

      const endInput = document.createElement('input')
      endInput.type = 'hidden'
      endInput.name = 'end_time'
      endInput.value = endTime
      form.appendChild(endInput)
    }

    // Tag switches are already being submitted as enabled_tags[]
    // The controller will convert these to disabled_tags
    // No additional processing needed here

    // No validation needed - user can apply any combination of filters
  }

  // Update visual indicator based on activeValue
  updateIndicator() {
    if (this.hasIndicatorTarget) {
      if (this.activeValue) {
        this.indicatorTarget.classList.add("global-filters-active")
      } else {
        this.indicatorTarget.classList.remove("global-filters-active")
      }
    }
  }

  // Called when activeValue changes
  activeValueChanged() {
    this.updateIndicator()
  }
}
