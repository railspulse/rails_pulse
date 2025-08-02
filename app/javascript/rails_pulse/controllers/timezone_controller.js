import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { cachedAt: String, targetFrame: String }

  connect() {
    this.updateTimestamp()
    this.setupObserver()
    this.setupTurboFrameListener()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
    if (this.frameObserver) {
      this.frameObserver.disconnect()
    }
    if (this.documentObserver) {
      this.documentObserver.disconnect()
    }
    if (this.turboFrameListener) {
      document.removeEventListener('turbo:frame-load', this.turboFrameListener)
    }
  }

  setupObserver() {
    if (this.targetFrameValue) {
      // Try immediately
      this.updateTimestamp()

      // Also observe for when the frame appears or changes
      const observer = new MutationObserver(() => {
        const targetFrame = document.getElementById(this.targetFrameValue)
        if (targetFrame) {
          this.updateTimestamp()
          // Watch for attribute changes on the frame
          if (this.frameObserver) {
            this.frameObserver.disconnect()
          }
          this.frameObserver = new MutationObserver(() => {
            this.updateTimestamp()
          })
          this.frameObserver.observe(targetFrame, {
            attributes: true,
            attributeFilter: ['data-cached-at'],
            childList: true,
            subtree: true
          })
        }
      })

      // Watch the whole document for the frame to appear
      observer.observe(document.body, { childList: true, subtree: true })
      this.documentObserver = observer
    }
  }

  cachedAtValueChanged() {
    this.updateTimestamp()
  }

  setupTurboFrameListener() {
    if (this.targetFrameValue) {
      this.turboFrameListener = (event) => {
        // Check if the loaded frame matches our target frame
        if (event.target && event.target.id === this.targetFrameValue) {
          // Update timestamp when our target frame loads
          this.updateTimestamp()
        }
      }
      document.addEventListener('turbo:frame-load', this.turboFrameListener)
    }
  }

  updateTimestamp() {
    let cachedAtValue = this.cachedAtValue

    // If no direct cached value but we have a target frame, try to get it from there
    if (!cachedAtValue && this.targetFrameValue) {
      const targetFrame = document.getElementById(this.targetFrameValue)
      if (targetFrame) {
        cachedAtValue = targetFrame.dataset.cachedAt
      }
    }

    if (cachedAtValue) {
      try {
        const date = new Date(cachedAtValue)
        const localTimeString = date.toLocaleString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        })
        this.element.title = `Last updated: ${localTimeString}`
      } catch (e) {
        this.element.title = 'Cache time unavailable'
      }
    } else {
      this.element.title = 'Cache time unavailable'
    }
  }
}
