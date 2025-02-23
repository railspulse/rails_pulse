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
    console.log("Toggling color scheme to", current)
    this.html.setAttribute("data-color-scheme", current)
    localStorage.setItem(this.storageKey, current)
  }
}
