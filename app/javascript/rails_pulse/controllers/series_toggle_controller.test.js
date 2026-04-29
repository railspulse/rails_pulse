import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import SeriesToggleController from './series_toggle_controller'
import { mountController } from '../../test/setup'

const HTML = `
  <button
    data-controller="series-toggle"
    data-series-toggle-series-name-value="p95"
    data-series-toggle-chart-id-value="main-chart"
    data-active="true">
    P95
  </button>
`

describe('SeriesToggleController', () => {
  let app, element, teardown

  beforeEach(async () => {
    ;({ app, element, teardown } = await mountController('series-toggle', SeriesToggleController, HTML))
  })

  afterEach(() => teardown())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'series-toggle')
  }

  // # Toggle

  it('sets data-active to "false" when currently active', () => {
    element.dataset.active = 'true'
    ctrl().toggle()
    expect(element.dataset.active).toBe('false')
  })

  it('sets data-active to "true" when currently inactive', () => {
    element.dataset.active = 'false'
    ctrl().toggle()
    expect(element.dataset.active).toBe('true')
  })

  it('dispatches rails-pulse:toggle-series with the correct chart and series', () => {
    const received = []
    document.addEventListener('rails-pulse:toggle-series', e => received.push(e.detail))
    ctrl().toggle()
    expect(received).toHaveLength(1)
    expect(received[0]).toEqual({ chartId: 'main-chart', seriesName: 'p95' })
  })

  it('dispatches on every toggle call', () => {
    const received = []
    document.addEventListener('rails-pulse:toggle-series', e => received.push(e.detail))
    ctrl().toggle()
    ctrl().toggle()
    expect(received).toHaveLength(2)
  })
})
