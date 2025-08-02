import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "menu" ]

  show(event) {
    // Use CSS custom properties instead of inline styles for CSP safety
    this.menuTarget.style.setProperty('--context-menu-x', `${event.clientX - 5}px`)
    this.menuTarget.style.setProperty('--context-menu-y', `${event.clientY - 5}px`)
    
    // Add CSS class to apply positioning via CSS custom properties
    this.menuTarget.classList.add('positioned')
    
    setTimeout(() => this.menuTarget.showPopover(), 150)
  }
}
