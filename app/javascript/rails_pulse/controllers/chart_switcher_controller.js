import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "button", "toggleGroup", "chartTypeInput"]
  static values = {
    selected: { type: String, default: "response_time" }
  }

  connect() {
    const urlParams = new URLSearchParams(window.location.search)
    const chartType = urlParams.get('chart_type')
    if (chartType) {
      this.selectedValue = chartType
    }
    this.showSelected()
    this.syncHiddenInput()
  }

  switch(event) {
    const fromType = this.selectedValue
    const toType = event.currentTarget.dataset.chartType

    const fromContainer = this.chartTargets.find(el => el.dataset.chartType === fromType)
    const toContainer = this.chartTargets.find(el => el.dataset.chartType === toType)

    this.selectedValue = toType
    this.showSelected()

    const url = new URL(window.location.href)
    url.searchParams.set('chart_type', toType)
    window.history.replaceState({}, '', url)

    this.syncHiddenInput()

    this.dispatch('switched', {
      detail: {
        fromId: fromContainer?.dataset.chartId,
        toId: toContainer?.dataset.chartId
      }
    })
  }

  syncHiddenInput() {
    if (this.hasChartTypeInputTarget) {
      this.chartTypeInputTarget.value = this.selectedValue
    }
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
