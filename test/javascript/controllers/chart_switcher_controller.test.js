import { describe, it, expect, afterEach, vi } from 'vitest'
import ChartSwitcherController from '../../../app/javascript/rails_pulse/controllers/chart_switcher_controller'
import { mountController } from '../setup'

const HTML = `
  <div data-controller="chart-switcher">
    <button data-chart-switcher-target="button" data-chart-type="response_time" data-action="click->chart-switcher#switch">Response Time</button>
    <button data-chart-switcher-target="button" data-chart-type="throughput"    data-action="click->chart-switcher#switch">Throughput</button>

    <div data-chart-switcher-target="chart" data-chart-type="response_time" data-chart-id="chart-rt">Chart RT</div>
    <div data-chart-switcher-target="chart" data-chart-type="throughput"    data-chart-id="chart-tp">Chart TP</div>

    <input type="hidden" data-chart-switcher-target="chartTypeInput" />
  </div>
`

describe('ChartSwitcherController', () => {
  let app, element, teardown

  afterEach(() => teardown?.())

  async function mount(search = '') {
    vi.stubGlobal('location', { href: `http://localhost/${search}`, search })
    vi.spyOn(window.history, 'replaceState').mockImplementation(() => {})
    ;({ app, element, teardown } = await mountController('chart-switcher', ChartSwitcherController, HTML))
  }

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'chart-switcher')
  }

  function charts() {
    return [...element.querySelectorAll('[data-chart-switcher-target="chart"]')]
  }

  function buttons() {
    return [...element.querySelectorAll('[data-chart-switcher-target="button"]')]
  }

  function hiddenInput() {
    return element.querySelector('[data-chart-switcher-target="chartTypeInput"]')
  }

  // # Connect — default selection

  it('shows the default chart (response_time) and hides others', async () => {
    await mount()
    const [rt, tp] = charts()
    expect(rt.style.display).toBe('block')
    expect(tp.style.display).toBe('none')
  })

  it('marks the default button as active', async () => {
    await mount()
    const [rtBtn, tpBtn] = buttons()
    expect(rtBtn.dataset.active).toBe('true')
    expect(tpBtn.dataset.active).toBe('false')
  })

  it('syncs the hidden input to the default selection', async () => {
    await mount()
    expect(hiddenInput().value).toBe('response_time')
  })

  // # Connect — URL param overrides default

  it('uses the chart_type URL param when present', async () => {
    await mount('?chart_type=throughput')
    const [rt, tp] = charts()
    expect(tp.style.display).toBe('block')
    expect(rt.style.display).toBe('none')
  })

  // # Switch

  it('shows the selected chart after switching', async () => {
    await mount()
    const tpBtn = buttons()[1]
    const switchEvent = { currentTarget: tpBtn }
    ctrl().switch(switchEvent)
    const [rt, tp] = charts()
    expect(tp.style.display).toBe('block')
    expect(rt.style.display).toBe('none')
  })

  it('updates button active states after switching', async () => {
    await mount()
    ctrl().switch({ currentTarget: buttons()[1] })
    const [rtBtn, tpBtn] = buttons()
    expect(tpBtn.dataset.active).toBe('true')
    expect(rtBtn.dataset.active).toBe('false')
  })

  it('updates the URL via history.replaceState', async () => {
    await mount()
    ctrl().switch({ currentTarget: buttons()[1] })
    expect(window.history.replaceState).toHaveBeenCalled()
    const url = String(window.history.replaceState.mock.calls[0][2])
    expect(url).toContain('chart_type=throughput')
  })

  it('syncs the hidden input after switching', async () => {
    await mount()
    ctrl().switch({ currentTarget: buttons()[1] })
    expect(hiddenInput().value).toBe('throughput')
  })
})
