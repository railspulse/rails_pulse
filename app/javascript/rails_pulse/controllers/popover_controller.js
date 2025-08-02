import { Controller } from "@hotwired/stimulus"
import { computePosition, flip, shift, offset, autoUpdate } from "@floating-ui/dom"

export default class extends Controller {
  static targets = [ "button", "menu" ]
  static values  = { placement: { type: String, default: "bottom" } }

  #showTimer = null
  #hideTimer = null

  initialize() {
    this.orient = this.orient.bind(this)
  }

  connect() {
    this.cleanup = autoUpdate(this.buttonTarget, this.menuTarget, this.orient)
  }

  disconnect() {
    this.cleanup()
  }

  show() {
    this.menuTarget.showPopover({ source: this.buttonTarget })
    this.loadOperationDetailsIfNeeded()
  }

  hide() {
    this.menuTarget.hidePopover()
  }

  toggle() {
    this.menuTarget.togglePopover({ source: this.buttonTarget })
    this.loadOperationDetailsIfNeeded()
  }

  debouncedShow() {
    clearTimeout(this.#hideTimer)
    this.#showTimer = setTimeout(() => this.show(), 700)
  }

  debouncedHide() {
    clearTimeout(this.#showTimer)
    this.#hideTimer = setTimeout(() => this.hide(), 300)
  }

  orient() {
    computePosition(this.buttonTarget, this.menuTarget, this.#options).then(({x, y}) => {
      // Use CSS custom properties for CSP compliance
      this.menuTarget.style.setProperty('--popover-x', `${x}px`)
      this.menuTarget.style.setProperty('--popover-y', `${y}px`)
      // Add class to apply the positioning
      this.menuTarget.classList.add('positioned')
    })
  }

  loadOperationDetailsIfNeeded() {
    // Check if this popover has operation details to load
    const operationUrl = this.menuTarget.dataset.operationUrl
    if (!operationUrl) return
    
    // Find the turbo frame inside the popover
    const turboFrame = this.menuTarget.querySelector('turbo-frame')
    if (!turboFrame) return
    
    // Only load if not already loaded (check if still shows loading content)
    // Use CSP-safe method to check for loading content
    const hasLoadingContent = this.hasLoadingContent(turboFrame)
    if (!hasLoadingContent) return
    
    // Set the src attribute to trigger the turbo frame loading
    turboFrame.src = operationUrl
  }

  // CSP-safe method to check for loading content
  hasLoadingContent(element) {
    // Use textContent instead of innerHTML to avoid CSP issues
    const textContent = element.textContent || ''
    return textContent.includes('Loading operation details')
  }

  get #options() {
    return { placement: this.placementValue, middleware: [offset(4), flip(), shift({padding: 4})] }
  }
}