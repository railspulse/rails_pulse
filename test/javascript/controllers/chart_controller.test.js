import { describe, it, expect, afterEach } from 'vitest'
import ChartController from '../../../app/javascript/rails_pulse/controllers/chart_controller'
import { mountController } from '../setup'

const HTML = `
  <div
    data-controller="chart"
    data-chart-config-value="{}"
  ></div>
`

describe('ChartController', () => {
  let app, element, teardown

  afterEach(() => teardown?.())

  async function mount() {
    ;({ app, element, teardown } = await mountController('chart', ChartController, HTML))
  }

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'chart')
  }

  // # Tooltip formatters — null value handling

  describe('auto_date_tooltip', () => {
    it('renders 0 instead of null when a series value is null', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('auto_date_tooltip')

      const params = [
        {
          axisValue: 1700000000000,
          axisValueLabel: 'Nov 14',
          seriesName: 'P95',
          marker: '●',
          value: [1700000000000, null]
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P95: 0')
      expect(html).not.toContain('null')
    })

    it('renders the rounded number when a series value is a number', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('auto_date_tooltip')

      const params = [
        {
          axisValue: 1700000000000,
          axisValueLabel: 'Nov 14',
          seriesName: 'P95',
          marker: '●',
          value: [1700000000000, 123.7]
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P95: 124')
    })
  })

  describe('tooltip_with_timestamp', () => {
    it('renders 0 instead of null when a series value is null', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('tooltip_with_timestamp')

      const params = [
        {
          axisValue: 1700000000000,
          axisValueLabel: 'Nov 14',
          seriesName: 'P99',
          marker: '●',
          value: [1700000000000, null]
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P99: 0')
      expect(html).not.toContain('null')
    })

    it('renders the rounded number when a series value is a number', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('tooltip_with_timestamp')

      const params = [
        {
          axisValue: 1700000000000,
          axisValueLabel: 'Nov 14',
          seriesName: 'P99',
          marker: '●',
          value: [1700000000000, 87.3]
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P99: 87')
    })

    it('renders 0 instead of null for a plain null value (non-array)', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('tooltip_with_timestamp')

      const params = [
        {
          axisValue: '2024-01-01',
          axisValueLabel: 'Jan 1',
          seriesName: 'Count',
          marker: '●',
          value: null
        }
      ]

      const html = formatter(params)
      expect(html).toContain('Count: 0')
      expect(html).not.toContain('null')
    })
  })

  describe('sparkline_tooltip', () => {
    it('renders 0 instead of null when the data value is null', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('sparkline_tooltip')

      const params = [
        {
          axisValue: '12:00',
          seriesName: 'P95',
          marker: '●',
          value: null
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P95: 0')
      expect(html).not.toContain('null')
    })

    it('renders the rounded number when the data value is a number', async () => {
      await mount()
      const formatter = ctrl().getSafeFormatter('sparkline_tooltip')

      const params = [
        {
          axisValue: '12:00',
          seriesName: 'P95',
          marker: '●',
          value: 42.9
        }
      ]

      const html = formatter(params)
      expect(html).toContain('P95: 43')
    })
  })
})
