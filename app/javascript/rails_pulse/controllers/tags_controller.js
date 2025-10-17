import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["addButton", "dropdown", "container", "removeButton"]

  connect() {
    // Close dropdown when clicking outside
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
  }

  toggleDropdown(event) {
    event.stopPropagation()
    const dropdown = this.dropdownTarget

    if (dropdown.style.display === "none" || dropdown.style.display === "") {
      dropdown.style.display = "block"
    } else {
      dropdown.style.display = "none"
    }
  }

  clickOutside(event) {
    if (!this.hasDropdownTarget) return

    // Check if click is outside the container
    if (this.hasContainerTarget && !this.containerTarget.contains(event.target)) {
      this.dropdownTarget.style.display = "none"
    }
  }
}
