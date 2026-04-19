import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip"]

  showTooltip(event) {
    const bar = event.currentTarget
    const tooltip = this.tooltipTarget

    tooltip.querySelector('[data-flame-type]').textContent = bar.dataset.opType.replace(/_/g, ' ')
    tooltip.querySelector('[data-flame-label]').textContent = bar.dataset.opLabel
    tooltip.querySelector('[data-flame-duration]').textContent = bar.dataset.opDuration
    tooltip.querySelector('[data-flame-impact]').textContent = bar.dataset.opImpact

    tooltip.classList.remove('hidden')
  }

  moveTooltip(event) {
    const tooltip = this.tooltipTarget
    if (tooltip.classList.contains('hidden')) return

    const x = Math.min(event.clientX + 16, window.innerWidth - 320)
    const y = Math.max(event.clientY - 80, 8)
    tooltip.style.left = `${x}px`
    tooltip.style.top = `${y}px`
  }

  hideTooltip() {
    this.tooltipTarget.classList.add('hidden')
  }

  navigate(event) {
    const url = event.currentTarget.dataset.opUrl
    if (url) window.location.href = url
  }
}
