import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.storageKey = "color-scheme"
    this.html = document.documentElement
    const saved = localStorage.getItem(this.storageKey)
    if (saved) {
      this.html.setAttribute("data-color-scheme", saved)
    }
  }

  toggle(event) {
    event.preventDefault()
    const current = this.html.getAttribute("data-color-scheme") === "dark" ? "light" : "dark"
    this.html.setAttribute("data-color-scheme", current)
    localStorage.setItem(this.storageKey, current)
    // Notify listeners (e.g., charts) that scheme changed
    document.dispatchEvent(new CustomEvent('rails-pulse:color-scheme-changed', { detail: { scheme: current }}))
  }
}
