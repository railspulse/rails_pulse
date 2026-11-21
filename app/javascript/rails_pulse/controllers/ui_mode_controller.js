import { Controller } from "@hotwired/stimulus"

// Switches between the default look and the terminal-style "TUI" look. The
// mode lives on <html> so the inline script in the layout can restore it
// before the first paint, and the stylesheet does the rest.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.storageKey = "rails-pulse-ui"
    this.html = document.documentElement
    this.restore()
    this.sync()
  }

  // The layout's inline script normally does this before first paint. A host
  // Content Security Policy can block that script, so apply the stored mode
  // here as well.
  restore() {
    try {
      if (localStorage.getItem(this.storageKey) === "tui") this.html.setAttribute("data-ui", "tui")
    } catch {
      // Storage can be unavailable (private mode); the default look applies.
    }
  }

  toggle(event) {
    event.preventDefault()
    const tui = !this.tui
    if (tui) {
      this.html.setAttribute("data-ui", "tui")
    } else {
      this.html.removeAttribute("data-ui")
    }
    try {
      localStorage.setItem(this.storageKey, tui ? "tui" : "default")
    } catch {
      // Storage can be unavailable (private mode); the toggle still works for this page.
    }
    this.sync()
    // A monospace font changes text metrics, so charts need to re-measure.
    window.dispatchEvent(new Event("resize"))
  }

  get tui() {
    return this.html.getAttribute("data-ui") === "tui"
  }

  sync() {
    this.toggleTargets.forEach((toggle) => toggle.setAttribute("aria-pressed", String(this.tui)))
  }
}
