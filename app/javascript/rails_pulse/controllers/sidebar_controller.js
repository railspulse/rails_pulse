import { Controller } from "@hotwired/stimulus"

// Collapses the sidebar to an icon rail. The state lives on <html> so the
// inline script in the layout can restore it before the first paint.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.storageKey = "rails-pulse-sidebar"
    this.html = document.documentElement
    this.sync()
  }

  toggle(event) {
    event.preventDefault()
    const collapsed = !this.collapsed
    if (collapsed) {
      this.html.setAttribute("data-sidebar", "collapsed")
    } else {
      this.html.removeAttribute("data-sidebar")
    }
    try {
      localStorage.setItem(this.storageKey, collapsed ? "collapsed" : "expanded")
    } catch (_error) {
      // Storage can be unavailable (private mode); the toggle still works for this page.
    }
    this.sync()
    // Charts size themselves from their container and only re-measure on resize.
    window.dispatchEvent(new Event("resize"))
  }

  get collapsed() {
    return this.html.getAttribute("data-sidebar") === "collapsed"
  }

  sync() {
    if (!this.hasToggleTarget) return
    this.toggleTarget.setAttribute("aria-expanded", String(!this.collapsed))
    this.toggleTarget.setAttribute("aria-label", this.collapsed ? "Expand sidebar" : "Collapse sidebar")
    const label = this.toggleTarget.querySelector("span")
    if (label) label.textContent = this.collapsed ? "Expand" : "Collapse"
  }
}
