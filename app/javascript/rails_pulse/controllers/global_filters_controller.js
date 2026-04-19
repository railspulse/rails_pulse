import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["wrapper", "dialog", "indicator", "form"]
  static values = {
    active: { type: Boolean, default: false }
  }

  connect() {
    this.updateIndicator()
  }

  // Open the global filters dialog
  open(event) {
    event.preventDefault()

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

  // Handle form submission
  submit(event) {
    // If clear button was clicked, let it through as-is
    if (event.submitter && event.submitter.name === "clear") {
      return
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
