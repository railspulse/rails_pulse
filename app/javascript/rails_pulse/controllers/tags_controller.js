import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["addButton", "dropdown", "container", "removeButton", "ignoredDialog"]

  connect() {
    // Close dropdown when clicking outside
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)

    // Show ignored dialog if the ignored tag was just added
    if (this.hasIgnoredDialogTarget) {
      this.showIgnoredDialog()
    }
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

  selectTag(event) {
    const tag = event.currentTarget.dataset.tag

    // Close dropdown immediately
    if (this.hasDropdownTarget) {
      this.dropdownTarget.style.display = "none"
    }

    // Show dialog if ignored tag is selected
    // Wait for Turbo Stream to replace the content
    if (tag === "ignored") {
      setTimeout(() => {
        const dialogs = document.querySelectorAll('[data-rails-pulse--tags-target="ignoredDialog"]')
        if (dialogs.length > 0) {
          dialogs[dialogs.length - 1].showModal()
        }
      }, 200)
    }
  }

  showIgnoredDialog() {
    if (this.hasIgnoredDialogTarget) {
      this.ignoredDialogTarget.showModal()
    }
  }
}
