import { Controller } from "@hotwired/stimulus"

// CSP-Safe Icon Controller for Rails Pulse
// Integrates with window.RailsPulseIcons for pre-compiled icon access
export default class extends Controller {
  static values = {
    name: String,      // Icon name (e.g., "menu", "chevron-right")
    width: String,     // Icon width (default: "24")
    height: String,    // Icon height (default: "24")
    strokeWidth: String // Stroke width (default: "2")
  }

  static classes = ["loading", "error", "loaded"]

  connect() {
    this.renderIcon()
  }

  // Called when icon name changes
  nameValueChanged() {
    this.renderIcon()
  }

  // CSP-safe icon rendering using DOM methods
  renderIcon() {
    // Clear any existing content
    this.clearIcon()

    // Add loading state
    this.element.classList.add(...this.loadingClasses)
    this.element.classList.remove(...this.errorClasses, ...this.loadedClasses)

    // Get icon name
    const iconName = this.nameValue
    if (!iconName) {
      this.handleError(`Icon name is required`)
      return
    }

    // Check if RailsPulseIcons is available
    if (!window.RailsPulseIcons) {
      this.handleError(`RailsPulseIcons not loaded`)
      return
    }

    // Get icon SVG content
    const svgContent = window.RailsPulseIcons.get(iconName)
    if (!svgContent) {
      this.handleError(`Icon '${iconName}' not found`)
      return
    }

    // Create SVG element using CSP-safe DOM methods
    try {
      const svg = this.createSVGElement(svgContent)
      this.element.appendChild(svg)
      
      // Update state to loaded
      this.element.classList.remove(...this.loadingClasses, ...this.errorClasses)
      this.element.classList.add(...this.loadedClasses)
      
      // Set aria-label for accessibility
      this.element.setAttribute('aria-label', `${iconName} icon`)
      
    } catch (error) {
      this.handleError(`Failed to render icon '${iconName}': ${error.message}`)
    }
  }

  // Create SVG element using CSP-safe DOM methods
  createSVGElement(svgContent) {
    // Create SVG element with proper namespace
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    
    // Set SVG attributes
    svg.setAttribute('width', this.widthValue || '24')
    svg.setAttribute('height', this.heightValue || '24')
    svg.setAttribute('viewBox', '0 0 24 24')
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('stroke-width', this.strokeWidthValue || '2')
    svg.setAttribute('stroke-linecap', 'round')
    svg.setAttribute('stroke-linejoin', 'round')
    
    // Use the RailsPulseIcons render method for CSP-safe injection
    if (window.RailsPulseIcons.render) {
      // Clear the element and let RailsPulseIcons handle the rendering
      const tempDiv = document.createElement('div')
      const success = window.RailsPulseIcons.render(this.nameValue, tempDiv, {
        width: this.widthValue || '24',
        height: this.heightValue || '24'
      })
      
      if (success && tempDiv.firstChild) {
        return tempDiv.firstChild
      }
    }
    
    // Fallback: manually parse SVG content using DOMParser
    const parser = new DOMParser()
    const svgDoc = parser.parseFromString(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${this.widthValue || '24'}" height="${this.heightValue || '24'}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${this.strokeWidthValue || '2'}" stroke-linecap="round" stroke-linejoin="round">${svgContent}</svg>`,
      'image/svg+xml'
    )
    
    const parsedSvg = svgDoc.documentElement
    if (parsedSvg.nodeName === 'parsererror') {
      throw new Error('Invalid SVG content')
    }
    
    // Import the node into the current document
    return document.importNode(parsedSvg, true)
  }

  // Clear icon content safely
  clearIcon() {
    // Use DOM methods to clear content (CSP-safe)
    while (this.element.firstChild) {
      this.element.removeChild(this.element.firstChild)
    }
  }

  // Handle icon loading errors
  handleError(message) {
    console.warn(`[Rails Pulse Icon Controller] ${message}`)
    
    // Clear any existing content
    this.clearIcon()
    
    // Update state to error
    this.element.classList.remove(...this.loadingClasses, ...this.loadedClasses)
    this.element.classList.add(...this.errorClasses)
    
    // Create fallback placeholder using CSP-safe methods
    this.createErrorPlaceholder()
    
    // Set aria-label for accessibility
    this.element.setAttribute('aria-label', 'Icon not available')
  }

  // Create error placeholder using CSP-safe DOM methods
  createErrorPlaceholder() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('width', this.widthValue || '24')
    svg.setAttribute('height', this.heightValue || '24')
    svg.setAttribute('viewBox', '0 0 24 24')
    svg.setAttribute('fill', 'currentColor')
    svg.setAttribute('opacity', '0.3')
    
    // Create a simple rectangle as placeholder
    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect')
    rect.setAttribute('width', '20')
    rect.setAttribute('height', '20')
    rect.setAttribute('x', '2')
    rect.setAttribute('y', '2')
    rect.setAttribute('rx', '2')
    
    svg.appendChild(rect)
    this.element.appendChild(svg)
  }

  // Debug method to list available icons
  listAvailableIcons() {
    if (window.RailsPulseIcons?.list) {
      console.log('Available icons:', window.RailsPulseIcons.list())
    } else {
      console.warn('RailsPulseIcons not loaded or list method not available')
    }
  }
}