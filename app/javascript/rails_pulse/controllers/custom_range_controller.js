import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectWrapper", "pickerWrapper"]

  connect() {
    // Show picker on load if custom is already selected
    const selectElement = this.selectWrapperTarget.querySelector('select')
    if (selectElement && selectElement.value === "custom") {
      this.showPicker()
      // Initialize flatpickr with the existing value if present
      this.initializeDatePicker()
    }
  }

  // When "Custom Range..." is selected from dropdown
  handleChange(event) {
    if (event.target.value === "custom") {
      this.showPicker()
      // Automatically open the datepicker calendar
      this.openDatePicker()
    }
  }

  // Show picker, hide select
  showPicker() {
    this.selectWrapperTarget.style.display = "none"
    this.pickerWrapperTarget.style.display = "flex"
  }

  // Open the flatpickr calendar
  openDatePicker() {
    // Wait a bit for the DOM to update and flatpickr to initialize
    setTimeout(() => {
      // Find the original hidden input that has the datepicker controller
      const hiddenInput = this.pickerWrapperTarget.querySelector('input[name*="custom_date_range"]')
      if (!hiddenInput) return

      // Get the datepicker controller from the hidden input
      const datepickerController = this.application.getControllerForElementAndIdentifier(
        hiddenInput,
        'rails-pulse--datepicker'
      )

      if (datepickerController && datepickerController.flatpickr) {
        datepickerController.flatpickr.open()
      }
    }, 50)
  }

  // Show select, hide picker
  showSelect() {
    this.pickerWrapperTarget.style.display = "none"
    this.selectWrapperTarget.style.display = "block"

    // Reset select to default value
    const selectElement = this.selectWrapperTarget.querySelector('select')
    if (selectElement) {
      selectElement.value = "last_day"
    }
  }

  // Initialize flatpickr with existing date value
  initializeDatePicker() {
    const dateInput = this.pickerWrapperTarget.querySelector('input[type="text"]')
    if (!dateInput || !dateInput.value) return

    // Get the datepicker controller
    const datepickerController = this.application.getControllerForElementAndIdentifier(
      dateInput,
      'rails-pulse--datepicker'
    )

    if (datepickerController && datepickerController.flatpickr) {
      const value = dateInput.value
      // Parse the "start to end" format
      if (value.includes(' to ')) {
        const [start, end] = value.split(' to ').map(d => d.trim())
        // Set the dates in flatpickr
        datepickerController.flatpickr.setDate([start, end], false)
      }
    }
  }
}
