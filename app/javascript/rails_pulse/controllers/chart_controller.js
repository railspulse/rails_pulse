import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: String,        // "bar", "line", "area", "sparkline"
    data: Object,        // Chart data
    options: Object,     // ECharts configuration
    theme: String        // ECharts theme
  }

  connect() {
    this.initializeChart()
    this.handleColorSchemeChange = this.onColorSchemeChange.bind(this)
    document.addEventListener('rails-pulse:color-scheme-changed', this.handleColorSchemeChange)
  }

  disconnect() {
    document.removeEventListener('rails-pulse:color-scheme-changed', this.handleColorSchemeChange)
    this.disposeChart()
  }

  // Main initialization with retry logic
  initializeChart() {
    this.retryCount = 0
    this.maxRetries = 100 // 5 seconds
    this.attemptInit()
  }

  attemptInit() {
    if (typeof echarts === 'undefined') {
      this.retryCount++
      if (this.retryCount >= this.maxRetries) {
        console.error('[RailsPulse] echarts not loaded after 5 seconds for', this.element.id)
        this.showError()
        return
      }
      setTimeout(() => this.attemptInit(), 50)
      return
    }

    this.renderChart()
  }

  renderChart() {
    try {
      // Initialize chart
      this.chart = echarts.init(this.element, this.themeValue || 'railspulse')

      // Build and set options
      const config = this.buildChartConfig()
      this.chart.setOption(config)

      // Apply current color scheme
      this.applyColorScheme()

      // Dispatch event for other controllers (event-based communication)
      document.dispatchEvent(new CustomEvent('stimulus:echarts:rendered', {
        detail: {
          containerId: this.element.id,
          chart: this.chart,
          controller: this
        }
      }))

      // Responsive resize
      this.resizeObserver = new ResizeObserver(() => {
        if (this.chart) {
          this.chart.resize()
        }
      })
      this.resizeObserver.observe(this.element)

      // Mark as rendered for tests
      this.element.setAttribute('data-chart-rendered', 'true')

    } catch (error) {
      console.error('[RailsPulse] Error initializing chart:', error)
      this.showError()
    }
  }

  buildChartConfig() {
    // Start with provided options
    const config = { ...this.optionsValue }

    // Process formatters (convert function strings to actual functions)
    this.processFormatters(config)

    // Set data (xAxis and series)
    this.setChartData(config)

    return config
  }

  setChartData(config) {
    const data = this.dataValue

    // Extract labels and values
    const labels = Object.keys(data).map(k => {
      const num = Number(k)
      return isNaN(num) ? k : num
    })

    const values = Object.values(data).map(v => {
      if (typeof v === 'object' && v !== null) {
        return v.value !== undefined ? v.value : v
      }
      return v
    })

    // Set xAxis data
    config.xAxis = config.xAxis || {}
    config.xAxis.type = 'category'
    config.xAxis.data = labels

    // Set yAxis
    config.yAxis = config.yAxis || {}
    config.yAxis.type = 'value'

    // Set series data
    if (Array.isArray(config.series)) {
      // If series is already an array, update first series
      config.series[0] = config.series[0] || {}
      config.series[0].type = this.typeValue
      config.series[0].data = values
    } else if (config.series && typeof config.series === 'object') {
      // If series is a single object (from helper), convert to array
      const seriesConfig = { ...config.series }
      config.series = [{
        type: this.typeValue,
        data: values,
        ...seriesConfig
      }]
    } else {
      // No series provided, create default
      config.series = [{
        type: this.typeValue,
        data: values
      }]
    }
  }

  processFormatters(config) {
    // Process tooltip formatter
    if (config.tooltip?.formatter && typeof config.tooltip.formatter === 'string') {
      config.tooltip.formatter = this.parseFormatter(config.tooltip.formatter)
    }

    // Process xAxis formatter
    if (config.xAxis?.axisLabel?.formatter && typeof config.xAxis.axisLabel.formatter === 'string') {
      config.xAxis.axisLabel.formatter = this.parseFormatter(config.xAxis.axisLabel.formatter)
    }

    // Process yAxis formatter
    if (config.yAxis?.axisLabel?.formatter && typeof config.yAxis.axisLabel.formatter === 'string') {
      config.yAxis.axisLabel.formatter = this.parseFormatter(config.yAxis.axisLabel.formatter)
    }
  }

  parseFormatter(formatterString) {
    // Remove function markers if present
    const cleanString = formatterString.replace(/__FUNCTION_START__|__FUNCTION_END__/g, '')

    // If it's a function string, parse it
    if (cleanString.trim().startsWith('function')) {
      try {
        // eslint-disable-next-line no-eval
        return eval(`(${cleanString})`)
      } catch (error) {
        console.error('[RailsPulse] Error parsing formatter function:', error)
        return cleanString
      }
    }
    return cleanString
  }

  showError() {
    this.element.classList.add('chart-error')
    this.element.innerHTML = '<p class="text-subtle p-4">Chart failed to load</p>'
  }

  // Public accessor for chart instance
  get chartInstance() {
    return this.chart
  }

  disposeChart() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }

    if (this.chart) {
      this.chart.dispose()
      this.chart = null
    }
  }

  // Action for dynamic updates
  update(event) {
    if (event.detail?.data) {
      this.dataValue = event.detail.data
    }
    if (event.detail?.options) {
      this.optionsValue = event.detail.options
    }
    if (this.chart) {
      const config = this.buildChartConfig()
      this.chart.setOption(config, true) // true = not merge
    }
  }

  // Color scheme management
  onColorSchemeChange() {
    this.applyColorScheme()
  }

  applyColorScheme() {
    if (!this.chart) return

    const scheme = document.documentElement.getAttribute('data-color-scheme')
    const isDark = scheme === 'dark'
    const axisColor = isDark ? '#ffffff' : '#999999'

    this.chart.setOption({
      xAxis: { axisLabel: { color: axisColor } },
      yAxis: { axisLabel: { color: axisColor } }
    })
  }
}
