import { describe, it, expect, afterEach, vi } from 'vitest'
import IndexController from '../../../app/javascript/rails_pulse/controllers/index_controller'
import { mountController, nextTick } from '../setup'

const CHART_ID = 'response_time_chart'

function buildHTML() {
  return `
    <div data-controller="index" data-index-chart-id-value="${CHART_ID}">
      <div data-index-target="chart" data-chart-id="${CHART_ID}"></div>
      <div id="index_table" data-index-target="indexTable"></div>
    </div>
  `
}

// Minimal stand-in for an ECharts instance: setupChartEventListeners only needs
// on() and a ZRender handle.
function buildChartStub() {
  const zr = { on: vi.fn(), off: vi.fn(), setCursorStyle: vi.fn() }
  return { on: vi.fn(), off: vi.fn(), getZr: () => zr, getOption: () => ({}) }
}

function countListeners(spy, type) {
  return spy.mock.calls.filter(([ eventType ]) => eventType === type).length
}

describe('IndexController', () => {
  let teardown

  afterEach(() => {
    teardown?.()
    vi.restoreAllMocks()
  })

  // # document-level mouseup listener lifecycle

  it('registers exactly one document mouseup listener on connect', async () => {
    const addSpy = vi.spyOn(document, 'addEventListener')
    ;({ teardown } = await mountController('index', IndexController, buildHTML()))

    expect(countListeners(addSpy, 'mouseup')).toBe(1)
  })

  it('does not stack document mouseup listeners when chart listeners are re-attached', async () => {
    const addSpy = vi.spyOn(document, 'addEventListener')
    const { app, element, teardown: t } = await mountController('index', IndexController, buildHTML())
    teardown = t

    const controller = app.getControllerForElementAndIdentifier(element, 'index')
    controller.chart = buildChartStub()

    // setupChartEventListeners runs again on every chart switch. It used to add a
    // fresh document mouseup listener each time, so every click anywhere on the
    // page re-ran handleZoomChange once per switch.
    controller.setupChartEventListeners()
    controller.setupChartEventListeners()
    controller.setupChartEventListeners()

    expect(countListeners(addSpy, 'mouseup')).toBe(1)
  })

  it('removes the document mouseup listener on disconnect', async () => {
    const removeSpy = vi.spyOn(document, 'removeEventListener')
    const { teardown: t } = await mountController('index', IndexController, buildHTML())
    teardown = t

    // Detaching the element lets Stimulus' MutationObserver run disconnect().
    document.body.innerHTML = ''
    await nextTick()

    expect(countListeners(removeSpy, 'mouseup')).toBe(1)
  })

  it('ignores document mouseup before a chart has rendered', async () => {
    const { app, element, teardown: t } = await mountController('index', IndexController, buildHTML())
    teardown = t

    const controller = app.getControllerForElementAndIdentifier(element, 'index')
    const handleZoomChange = vi.spyOn(controller, 'handleZoomChange')

    document.dispatchEvent(new window.MouseEvent('mouseup'))

    expect(handleZoomChange).not.toHaveBeenCalled()
  })
})
