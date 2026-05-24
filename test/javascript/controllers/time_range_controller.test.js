import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import TimeRangeController from '../../../app/javascript/rails_pulse/controllers/time_range_controller'
import { mountController } from '../setup'

const HTML = `
  <div data-controller="time-range" data-time-range-url-value="/time_range">
    <div popover>
      <div role="menu">
        <button data-preset="last_day" data-action="click->time-range#selectPreset">Last Day</button>
        <button data-action="click->time-range#showCustom">Custom</button>
      </div>
    </div>
    <div data-time-range-target="modalWrapper" style="display: none">
      <div data-time-range-target="modal">
        <input data-time-range-target="dateInput" type="text" value="" />
      </div>
    </div>
  </div>
`

describe('TimeRangeController', () => {
  let app, element, teardown

  beforeEach(async () => {
    // Stub form.submit() to prevent navigation
    vi.spyOn(HTMLFormElement.prototype, 'submit').mockImplementation(() => {})
    // Stub popover API (not implemented in JSDOM)
    HTMLElement.prototype.hidePopover = vi.fn()
    HTMLElement.prototype.showPopover = vi.fn()
    ;({ app, element, teardown } = await mountController('time-range', TimeRangeController, HTML))
  })

  afterEach(() => {
    teardown()
    document.body.style.overflow = ''
    vi.clearAllMocks()
    delete HTMLElement.prototype.hidePopover
    delete HTMLElement.prototype.showPopover
  })

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'time-range')
  }

  function modalWrapper() { return element.querySelector('[data-time-range-target="modalWrapper"]') }
  function dateInput() { return element.querySelector('[data-time-range-target="dateInput"]') }
  function popoverEl() { return element.querySelector('[popover]') }

  // # showCustom

  it('shows the modal wrapper', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    expect(modalWrapper().style.display).toBe('flex')
  })

  it('locks body scroll', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    expect(document.body.style.overflow).toBe('hidden')
  })

  it('hides the popover menu', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    expect(popoverEl().hidePopover).toHaveBeenCalledOnce()
  })

  // # closeModal / cancelCustom

  it('closeModal hides the modal wrapper', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    ctrl().closeModal()
    expect(modalWrapper().style.display).toBe('none')
  })

  it('closeModal restores body scroll', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    ctrl().closeModal()
    expect(document.body.style.overflow).toBe('')
  })

  it('cancelCustom clears the date input', () => {
    dateInput().value = '2024-01-01 to 2024-01-31'
    ctrl().cancelCustom({ preventDefault: vi.fn() })
    expect(dateInput().value).toBe('')
  })

  it('cancelCustom closes the modal', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    ctrl().cancelCustom({ preventDefault: vi.fn() })
    expect(modalWrapper().style.display).toBe('none')
  })

  // # closeOnClickOutside

  it('cancels when click target is the modal wrapper', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    ctrl().closeOnClickOutside({ target: modalWrapper(), preventDefault: vi.fn() })
    expect(modalWrapper().style.display).toBe('none')
  })

  it('does not close when click target is inside the modal', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    ctrl().closeOnClickOutside({ target: dateInput(), preventDefault: vi.fn() })
    expect(modalWrapper().style.display).toBe('flex')
  })

  // # applyCustom

  it('closes the modal after applying', () => {
    ctrl().showCustom({ preventDefault: vi.fn() })
    dateInput().value = '2024-01-01 to 2024-01-31'
    ctrl().applyCustom({ preventDefault: vi.fn() })
    expect(modalWrapper().style.display).toBe('none')
  })

  it('submits the form with start and end times', () => {
    dateInput().value = '2024-01-01 to 2024-01-31'
    ctrl().applyCustom({ preventDefault: vi.fn() })
    expect(HTMLFormElement.prototype.submit).toHaveBeenCalledOnce()
    const form = document.body.querySelector('form[action="/time_range"]')
    expect(form.querySelector('[name="start_time"]').value).toBe('2024-01-01')
    expect(form.querySelector('[name="end_time"]').value).toBe('2024-01-31')
  })

  it('alerts and does not submit when date range is missing', () => {
    vi.stubGlobal('alert', vi.fn())
    dateInput().value = ''
    ctrl().applyCustom({ preventDefault: vi.fn() })
    expect(window.alert).toHaveBeenCalledOnce()
    expect(HTMLFormElement.prototype.submit).not.toHaveBeenCalled()
    vi.unstubAllGlobals()
  })

  // # selectPreset / submitTimeRange

  it('submits the form with the preset value', () => {
    ctrl().selectPreset({ preventDefault: vi.fn(), currentTarget: element.querySelector('[data-preset="last_day"]') })
    expect(HTMLFormElement.prototype.submit).toHaveBeenCalledOnce()
    const form = document.body.querySelector('form[action="/time_range"]')
    expect(form.querySelector('[name="preset"]').value).toBe('last_day')
  })

  it('includes the _method=patch override in the submitted form', () => {
    ctrl().selectPreset({ preventDefault: vi.fn(), currentTarget: element.querySelector('[data-preset="last_day"]') })
    const form = document.body.querySelector('form[action="/time_range"]')
    expect(form.querySelector('[name="_method"]').value).toBe('patch')
  })
})
