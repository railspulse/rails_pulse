import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "button", "toggleGroup"]
  static values = {
    selected: { type: String, default: "response_time" }
  }

  connect() {
    this.showSelected()
  }

  switch(event) {
    this.selectedValue = event.currentTarget.dataset.chartType
    this.showSelected()
  }

  showSelected() {
    const selected = this.selectedValue

    // Show/hide charts
    this.chartTargets.forEach(el => {
      el.style.display = el.dataset.chartType === selected ? 'block' : 'none'
    })

    // Update tab active states
    this.buttonTargets.forEach(el => {
      el.dataset.active = el.dataset.chartType === selected ? 'true' : 'false'
    })

    // Show/hide contextual toggle groups
    this.toggleGroupTargets.forEach(el => {
      el.style.display = el.dataset.chartType === selected ? 'flex' : 'none'
    })
  }
}
