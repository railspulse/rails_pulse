import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    seriesName: String,
    chartId: String
  }

  connect() {
    this.syncPressed()
  }

  toggle() {
    const isActive = this.element.dataset.active !== 'false'
    this.element.dataset.active = isActive ? 'false' : 'true'
    this.syncPressed()

    document.dispatchEvent(new CustomEvent('rails-pulse:toggle-series', {
      detail: { chartId: this.chartIdValue, seriesName: this.seriesNameValue }
    }))
  }

  // data-active drives the styling; aria-pressed says the same thing to a
  // screen reader.
  syncPressed() {
    this.element.setAttribute('aria-pressed', String(this.element.dataset.active !== 'false'))
  }
}
