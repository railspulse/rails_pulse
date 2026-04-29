import { describe, it, expect, afterEach, vi } from 'vitest'
import CustomRangeController from './custom_range_controller'
import { mountController } from '../../test/setup'

function buildHTML({ mode = 'preset', value = 'last_day' } = {}) {
  return `
    <div data-controller="custom-range">
      <div data-custom-range-target="selectWrapper" style="display: block">
        <select data-mode="${mode}">
          <option value="last_day">Last Day</option>
          <option value="recent">Recent</option>
          <option value="custom" ${value === 'custom' ? 'selected' : ''}>Custom</option>
        </select>
      </div>
      <div data-custom-range-target="pickerWrapper" style="display: none">
        <input type="text" value="" />
      </div>
    </div>
  `
}

describe('CustomRangeController', () => {
  let app, element, teardown

  afterEach(() => teardown?.())

  async function mount(options = {}) {
    ;({ app, element, teardown } = await mountController('custom-range', CustomRangeController, buildHTML(options)))
    return app.getControllerForElementAndIdentifier(element, 'custom-range')
  }

  function selectWrapper() { return element.querySelector('[data-custom-range-target="selectWrapper"]') }
  function pickerWrapper() { return element.querySelector('[data-custom-range-target="pickerWrapper"]') }
  function select() { return element.querySelector('select') }

  // # Connect

  it('shows picker on connect when preset mode has "custom" selected', async () => {
    await mount({ mode: 'preset', value: 'custom' })
    expect(pickerWrapper().style.display).toBe('flex')
    expect(selectWrapper().style.display).toBe('none')
  })

  it('shows picker on connect when recent_custom mode has "custom" selected', async () => {
    await mount({ mode: 'recent_custom', value: 'custom' })
    expect(pickerWrapper().style.display).toBe('flex')
  })

  it('does not show picker on connect when a non-custom value is selected', async () => {
    await mount({ mode: 'preset', value: 'last_day' })
    expect(pickerWrapper().style.display).toBe('none')
    expect(selectWrapper().style.display).toBe('block')
  })

  // # showPicker

  it('hides the select wrapper', async () => {
    const ctrl = await mount()
    ctrl.showPicker()
    expect(selectWrapper().style.display).toBe('none')
  })

  it('shows the picker wrapper as flex', async () => {
    const ctrl = await mount()
    ctrl.showPicker()
    expect(pickerWrapper().style.display).toBe('flex')
  })

  // # showSelect

  it('shows the select wrapper', async () => {
    const ctrl = await mount({ value: 'custom' })
    ctrl.showSelect()
    expect(selectWrapper().style.display).toBe('block')
  })

  it('hides the picker wrapper', async () => {
    const ctrl = await mount({ value: 'custom' })
    ctrl.showSelect()
    expect(pickerWrapper().style.display).toBe('none')
  })

  it('resets select to "last_day" in preset mode', async () => {
    const ctrl = await mount({ value: 'custom' })
    ctrl.showSelect()
    expect(select().value).toBe('last_day')
  })

  it('resets select to "recent" in recent_custom mode', async () => {
    const ctrl = await mount({ mode: 'recent_custom', value: 'custom' })
    ctrl.showSelect()
    expect(select().value).toBe('recent')
  })

  // # handleChange — preset mode

  it('shows picker when "custom" is selected in preset mode', async () => {
    const ctrl = await mount({ mode: 'preset' })
    ctrl.handleChange({ target: Object.assign(select(), { value: 'custom' }) })
    expect(pickerWrapper().style.display).toBe('flex')
  })

  // # handleChange — recent_custom mode

  it('shows picker when "custom" is selected in recent_custom mode', async () => {
    const ctrl = await mount({ mode: 'recent_custom' })
    ctrl.handleChange({ target: Object.assign(select(), { value: 'custom' }) })
    expect(pickerWrapper().style.display).toBe('flex')
  })

  it('hides picker when "recent" is selected in recent_custom mode', async () => {
    const ctrl = await mount({ mode: 'recent_custom', value: 'custom' })
    ctrl.handleChange({ target: Object.assign(select(), { value: 'recent' }) })
    expect(pickerWrapper().style.display).toBe('none')
    expect(selectWrapper().style.display).toBe('block')
  })

  // # initializeDatePicker

  it('calls flatpickr.setDate with parsed start and end when input has a range value', async () => {
    // Need an input with a value in the pickerWrapper
    document.body.innerHTML = `
      <div data-controller="custom-range">
        <div data-custom-range-target="selectWrapper" style="display: block">
          <select data-mode="preset"><option value="last_day">Last Day</option></select>
        </div>
        <div data-custom-range-target="pickerWrapper" style="display: none">
          <input type="text" value="2024-01-01 to 2024-01-31" />
        </div>
      </div>
    `
    const localApp = (await import('@hotwired/stimulus')).Application.start()
    localApp.register('custom-range', CustomRangeController)
    await new Promise(r => setTimeout(r, 0))
    const el = document.querySelector('[data-controller="custom-range"]')
    const ctrl = localApp.getControllerForElementAndIdentifier(el, 'custom-range')

    const setDate = vi.fn()
    vi.spyOn(localApp, 'getControllerForElementAndIdentifier').mockReturnValue({ flatpickr: { setDate } })

    ctrl.initializeDatePicker()

    expect(setDate).toHaveBeenCalledWith(['2024-01-01', '2024-01-31'], false)
    localApp.stop()
    teardown = null
  })

  it('does nothing in initializeDatePicker when input has no value', async () => {
    const ctrl = await mount()
    // pickerWrapper has input[type="text"] with empty value — should not throw
    expect(() => ctrl.initializeDatePicker()).not.toThrow()
  })

  // # openDatePicker

  it('calls flatpickr.open after the setTimeout delay', async () => {
    document.body.innerHTML = `
      <div data-controller="custom-range">
        <div data-custom-range-target="selectWrapper" style="display: block">
          <select data-mode="preset"><option value="last_day">Last Day</option></select>
        </div>
        <div data-custom-range-target="pickerWrapper" style="display: none">
          <input name="custom_date_range" type="hidden" />
        </div>
      </div>
    `
    const localApp = (await import('@hotwired/stimulus')).Application.start()
    localApp.register('custom-range', CustomRangeController)
    await new Promise(r => setTimeout(r, 0))
    const el = document.querySelector('[data-controller="custom-range"]')
    const ctrl = localApp.getControllerForElementAndIdentifier(el, 'custom-range')

    const open = vi.fn()
    vi.spyOn(localApp, 'getControllerForElementAndIdentifier').mockReturnValue({ flatpickr: { open } })

    vi.useFakeTimers()
    ctrl.openDatePicker()
    vi.advanceTimersByTime(50)
    vi.useRealTimers()

    expect(open).toHaveBeenCalledOnce()
    localApp.stop()
    teardown = null
  })

  it('does nothing in openDatePicker when no matching input exists', async () => {
    const ctrl = await mount()
    // pickerWrapper has no input[name*="custom_date_range"] — should not throw
    vi.useFakeTimers()
    expect(() => { ctrl.openDatePicker(); vi.advanceTimersByTime(50) }).not.toThrow()
    vi.useRealTimers()
  })
})
