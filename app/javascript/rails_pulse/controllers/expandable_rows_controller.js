import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    // Delegate clicks from tbody to the nearest row
    const triggerRow = event.target.closest('tr')
    if (!triggerRow || triggerRow.closest('tbody') !== this.element) return

    // Ignore clicks on the details row itself
    if (triggerRow.classList.contains('operation-details-row')) return

    // Do not toggle when clicking the final Actions column
    const clickedCell = event.target.closest('td,th')
    if (clickedCell && clickedCell.parentElement === triggerRow) {
      const isLastCell = clickedCell.cellIndex === (triggerRow.cells.length - 1)
      if (isLastCell) return
    }

    event.preventDefault()
    event.stopPropagation()

    const detailsRow = triggerRow.nextElementSibling
    if (!detailsRow || detailsRow.tagName !== 'TR' || !detailsRow.classList.contains('operation-details-row')) return

    const isHidden = detailsRow.classList.contains('hidden')
    if (isHidden) {
      this.expand(triggerRow, detailsRow)
    } else {
      this.collapse(triggerRow, detailsRow)
    }
  }

  expand(triggerRow, detailsRow) {
    detailsRow.classList.remove('hidden')

    // Rotate chevron to point down
    const chevron = triggerRow.querySelector('.chevron')
    if (chevron) chevron.style.transform = 'rotate(90deg)'

    triggerRow.classList.add('expanded')

    // Lazy load operation details once
    const frame = detailsRow.querySelector('turbo-frame')
    if (frame && !frame.getAttribute('src')) {
      const url = frame.dataset.operationUrl
      if (url) frame.setAttribute('src', url)
    }
  }

  collapse(triggerRow, detailsRow) {
    detailsRow.classList.add('hidden')

    const chevron = triggerRow.querySelector('.chevron')
    if (chevron) chevron.style.transform = 'rotate(0deg)'

    triggerRow.classList.remove('expanded')
  }
}
