import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modalWrapper", "modal", "dateInput", "label", "trigger", "error"]
  static values = { url: String }

  selectPreset(event) {
    event.preventDefault()

    const button = event.currentTarget
    const preset = button.dataset.preset

    // Submit to server
    this.submitTimeRange(preset, null, null)
  }

  showCustom(event) {
    event.preventDefault()

    // Get the main menu popover
    const mainMenu = this.element.querySelector('[role="menu"]').closest('[popover]')

    // Hide the main menu
    if (mainMenu) {
      mainMenu.hidePopover()
    }

    // Show custom modal
    if (this.hasModalWrapperTarget) {
      this.modalWrapperTarget.style.display = 'flex'
      document.body.style.overflow = 'hidden'
    }
  }

  cancelCustom(event) {
    event.preventDefault()

    // Clear the date input
    if (this.hasDateInputTarget) {
      this.dateInputTarget.value = ""
    }

    // Hide custom modal
    this.closeModal()
  }

  closeModal() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    if (this.hasModalWrapperTarget) {
      this.modalWrapperTarget.style.display = 'none'
      document.body.style.overflow = ''
    }
  }

  // Escape closes the open calendar first (the date picker handles that
  // itself); a second press, or a press with no calendar open, closes the
  // dialog. The action listens in the capture phase so this runs before the
  // date picker's own handler has closed the calendar.
  closeOnEscape(event) {
    if (!this.hasModalWrapperTarget || this.modalWrapperTarget.style.display === 'none') return
    if (document.querySelector('.flatpickr-calendar.open')) return
    this.cancelCustom(event)
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }

  closeOnClickOutside(event) {
    if (this.hasModalTarget && event.target === this.modalWrapperTarget) {
      this.cancelCustom(event)
    }
  }

  applyCustom(event) {
    event.preventDefault()

    const dateRange = this.dateInputTarget.value

    if (!dateRange || !dateRange.includes(' to ')) {
      if (this.hasErrorTarget) this.errorTarget.hidden = false
      return
    }

    const [start, end] = dateRange.split(' to ').map(d => d.trim())

    // Hide custom modal
    this.closeModal()

    // Submit to server
    this.submitTimeRange(null, start, end)
  }

  submitTimeRange(preset, startTime, endTime) {
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = this.urlValue

    // Add CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const csrfInput = document.createElement('input')
      csrfInput.type = 'hidden'
      csrfInput.name = 'authenticity_token'
      csrfInput.value = csrfToken
      form.appendChild(csrfInput)
    }

    // Add method override for PATCH
    const methodInput = document.createElement('input')
    methodInput.type = 'hidden'
    methodInput.name = '_method'
    methodInput.value = 'patch'
    form.appendChild(methodInput)

    if (preset) {
      const presetInput = document.createElement('input')
      presetInput.type = 'hidden'
      presetInput.name = 'preset'
      presetInput.value = preset
      form.appendChild(presetInput)
    } else if (startTime && endTime) {
      const startInput = document.createElement('input')
      startInput.type = 'hidden'
      startInput.name = 'start_time'
      startInput.value = startTime
      form.appendChild(startInput)

      const endInput = document.createElement('input')
      endInput.type = 'hidden'
      endInput.name = 'end_time'
      endInput.value = endTime
      form.appendChild(endInput)
    }

    document.body.appendChild(form)
    form.submit()
  }
}
