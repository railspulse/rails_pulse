import { Controller } from "@hotwired/stimulus"

// Handles the 7d/14d/30d period toggle on the dashboard.
// Optimistically updates button active state on click.
export default class extends Controller {
  static targets = ["button"]

  select(event) {
    const clickedEl = event.currentTarget

    // Optimistic UI: immediately reflect the new active state
    this.buttonTargets.forEach(btn => {
      const isActive = btn === clickedEl
      btn.dataset.active = isActive ? "true" : "false"
      btn.style.background = isActive ? "var(--color-primary)" : "transparent"
      btn.style.color = isActive ? "var(--color-text-reversed)" : "var(--color-text-subtle)"
    })
  }
}
