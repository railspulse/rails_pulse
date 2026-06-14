import { describe, it, expect, afterEach, vi, beforeEach } from 'vitest'
import ChartController from '../../../app/javascript/rails_pulse/controllers/chart_controller'
import { mountController } from '../setup'

// ECharts is not available in JSDOM — stub it out so connect() doesn't loop
beforeEach(() => {
  vi.stubGlobal('echarts', undefined)
})

afterEach(() => {
  vi.unstubAllGlobals()
})

// Build minimal HTML for a chart controller element with time-pair data
function makeTimePairHTML(seriesData) {
  const data = JSON.stringify({ series: seriesData })
  const options = JSON.stringify({
    xAxis: { axisLabel: { formatter: 'time' } }
  })
  return `
    <div
      id="chart-test"
      data-controller="rails-pulse--chart"
      data-rails-pulse--chart-type-value="line"
      data-rails-pulse--chart-data-value='${data}'
      data-rails-pulse--chart-options-value='${options}'
    ></div>
  `
}

describe('ChartController', () => {
  let app, element, teardown

  afterEach(() => teardown?.())

  // Helper that mounts and returns a controller instance without rendering ECharts
  async function mountChart(html) {
    ;({ app, element, teardown } = await mountController('rails-pulse--chart', ChartController, html))
    return app.getControllerForElementAndIdentifier(element, 'rails-pulse--chart')
  }

  // # getSafeFormatter('time')

  describe('getSafeFormatter("time")', () => {
    it('returns a function', async () => {
      const html = makeTimePairHTML([{ name: 'P95', data: [] }])
      const ctrl = await mountChart(html)
      const formatter = ctrl.getSafeFormatter('time')
      expect(typeof formatter).toBe('function')
    })

    it('formats two different hour timestamps to two different labels', async () => {
      const html = makeTimePairHTML([{ name: 'P95', data: [] }])
      const ctrl = await mountChart(html)
      const formatter = ctrl.getSafeFormatter('time')

      const t10am = new Date('2024-01-15T10:00:00').getTime()
      const t11am = new Date('2024-01-15T11:00:00').getTime()

      const label10 = formatter(t10am)
      const label11 = formatter(t11am)

      expect(label10).not.toBe(label11)
      expect(label10).toBe('10:00')
      expect(label11).toBe('11:00')
    })
  })

  // # buildChartConfig() — formatter preservation

  describe('buildChartConfig() with time-pair data', () => {
    it('preserves a function formatter on xAxis.axisLabel (does not replace it with a string)', async () => {
      const t0 = new Date('2024-01-15T10:00:00').getTime()
      const t1 = new Date('2024-01-15T11:00:00').getTime()
      const seriesData = [{ name: 'P95', data: [[t0, 150], [t1, 200]] }]
      const html = makeTimePairHTML(seriesData)
      const ctrl = await mountChart(html)

      const config = ctrl.buildChartConfig()

      expect(typeof config.xAxis.axisLabel.formatter).toBe('function')
    })

    it('sets xAxis.type to "time" when data contains [timestamp, value] pairs', async () => {
      const t0 = new Date('2024-01-15T10:00:00').getTime()
      const t1 = new Date('2024-01-15T11:00:00').getTime()
      const seriesData = [{ name: 'P95', data: [[t0, 150], [t1, 200]] }]
      const html = makeTimePairHTML(seriesData)
      const ctrl = await mountChart(html)

      const config = ctrl.buildChartConfig()

      expect(config.xAxis.type).toBe('time')
    })

    it('produces two different formatted labels for two different hour timestamps', async () => {
      const t0 = new Date('2024-01-15T10:00:00').getTime()
      const t1 = new Date('2024-01-15T11:00:00').getTime()
      const seriesData = [{ name: 'P95', data: [[t0, 150], [t1, 200]] }]
      const html = makeTimePairHTML(seriesData)
      const ctrl = await mountChart(html)

      const config = ctrl.buildChartConfig()
      const formatter = config.xAxis.axisLabel.formatter

      expect(typeof formatter).toBe('function')
      expect(formatter(t0)).not.toBe(formatter(t1))
    })
  })
})
