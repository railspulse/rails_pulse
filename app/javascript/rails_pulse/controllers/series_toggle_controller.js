import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    seriesName: String,
    chartId: String
  }

  toggle() {
    const isActive = this.element.dataset.active !== 'false'
    this.element.dataset.active = isActive ? 'false' : 'true'

    document.dispatchEvent(new CustomEvent('rails-pulse:toggle-series', {
      detail: { chartId: this.chartIdValue, seriesName: this.seriesNameValue }
    }))
  }
}
