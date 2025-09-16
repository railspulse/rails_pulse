import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]
  static classes = ["collapsed"]

  connect() {
    this.collapse()
  }

  toggle() {
    if (this.element.classList.contains(this.collapsedClass)) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  collapse() {
    this.element.classList.add(this.collapsedClass)
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = "show more"
    }
  }

  expand() {
    this.element.classList.remove(this.collapsedClass)
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = "show less"
    }
  }
}
