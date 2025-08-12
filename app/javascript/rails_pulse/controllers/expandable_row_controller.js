import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "details", "chevron"]

  connect() {
    // Ensure details row is initially hidden
    this.detailsTarget.classList.add("hidden")
    this.loaded = false
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const isExpanded = !this.detailsTarget.classList.contains("hidden")
    console.log('Toggle clicked, currently expanded:', isExpanded)
    
    console.log('isExpanded', isExpanded)
    if (isExpanded) {
      console.log('Collapsing...')
      this.collapse()
    } else {
      console.log('Expanding...')
      this.expand()
    }
  }

  expand() {
    // Show details row
    this.detailsTarget.classList.remove("hidden")
    
    // Rotate chevron to point down
    this.chevronTarget.style.transform = "rotate(90deg)"
    
    // Add expanded state class to trigger row
    this.triggerTarget.classList.add("expanded")
    
    // Load content lazily on first expansion
    if (!this.loaded) {
      this.loadOperationDetails()
      this.loaded = true
    }
  }

  loadOperationDetails() {
    // Find the turbo frame and set its src to trigger loading
    const turboFrame = this.detailsTarget.querySelector('turbo-frame')
    if (turboFrame) {
      const operationUrl = turboFrame.dataset.operationUrl
      if (operationUrl) {
        turboFrame.src = operationUrl
      }
    }
  }

  collapse() {
    // Hide details row
    this.detailsTarget.classList.add("hidden")
    
    // Rotate chevron back to point right
    this.chevronTarget.style.transform = "rotate(0deg)"
    
    // Remove expanded state class from trigger row
    this.triggerTarget.classList.remove("expanded")
  }
}
