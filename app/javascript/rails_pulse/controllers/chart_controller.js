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
    this.handleSeriesToggle = this.onSeriesToggle.bind(this)
    document.addEventListener('rails-pulse:color-scheme-changed', this.handleColorSchemeChange)
    document.addEventListener('rails-pulse:toggle-series', this.handleSeriesToggle)
  }

  disconnect() {
    document.removeEventListener('rails-pulse:color-scheme-changed', this.handleColorSchemeChange)
    document.removeEventListener('rails-pulse:toggle-series', this.handleSeriesToggle)
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

    // Add hidden legend so series can be toggled programmatically via dispatchAction
    if (!config.legend) {
      config.legend = { show: false }
    }

    return config
  }

  setChartData(config) {
    const data = this.dataValue

    // Check if data is in multi-series format (has labels and series keys)
    if (data && typeof data === 'object' && data.labels && data.series) {
      // Multi-series format
      config.xAxis = config.xAxis || {}
      config.xAxis.type = 'category'
      config.xAxis.data = data.labels

      // Set yAxis
      config.yAxis = config.yAxis || {}
      config.yAxis.type = 'value'

      // Set series data from provided series array
      config.series = data.series.map((seriesData) => {
        return {
          type: this.typeValue,
          ...seriesData
        }
      })
    } else {
      // Single-series format (backward compatibility)
      // Extract labels and values
      const labels = Object.keys(data).map(k => {
        const num = Number(k)
        return isNaN(num) ? k : num
      })

      const values = Object.values(data).map(v => {
        if (typeof v === 'object' && v !== null) {
          // If object has value property, check if it has other properties too
          if (v.value !== undefined) {
            // If it has other properties (like itemStyle), return the whole object
            const keys = Object.keys(v)
            if (keys.length > 1 || (keys.length === 1 && keys[0] !== 'value')) {
              return v
            }
            // Otherwise just return the value
            return v.value
          }
          return v
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

    // If it's a function string, use safe formatter registry instead of eval()
    if (cleanString.trim().startsWith('function')) {
      // Extract formatter logic using safe parsing
      // Rather than eval(), we match against known safe patterns
      return this.getSafeFormatter(cleanString)
    }
    return cleanString
  }

  /**
   * Returns a safe formatter function based on the formatter string.
   * This prevents arbitrary code execution by using a whitelist approach.
   *
   * Security: Replaces eval() to prevent XSS and code injection attacks.
   */
  getSafeFormatter(formatterString) {
    // Whitelist of safe formatter patterns
    // Each pattern maps to a safe implementation
    const SAFE_FORMATTERS = {
      // Duration formatter (milliseconds)
      'duration_ms': (value) => {
        if (typeof value === 'number') {
          return value.toFixed(2) + ' ms'
        }
        return value
      },

      // Percentage formatter
      'percentage': (value) => {
        if (typeof value === 'number') {
          return value.toFixed(1) + '%'
        }
        return value
      },

      // Number with commas
      'number_delimited': (value) => {
        if (typeof value === 'number') {
          return value.toLocaleString()
        }
        return value
      },

      // Timestamp formatter
      'timestamp': (value) => {
        if (typeof value === 'number' || typeof value === 'string') {
          const date = new Date(value)
          return date.toLocaleString()
        }
        return value
      },

      // Date only (formatted as "Mon DD" to match Rails Pulse formatters)
      'date': (value) => {
        if (typeof value === 'number' || typeof value === 'string') {
          // Convert to number if string
          const numValue = typeof value === 'string' ? parseInt(value) : value
          const date = new Date(numValue)

          if (isNaN(date.getTime())) {
            return value.toString()
          }

          return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        }
        return value
      },

      // Time only (formatted as "HH:00" to match Rails Pulse formatters)
      'time': (value) => {
        if (typeof value === 'number' || typeof value === 'string') {
          // Convert to number if string
          const numValue = typeof value === 'string' ? parseInt(value) : value
          const date = new Date(numValue)

          const hours = date.getHours()
          if (isNaN(hours)) {
            return value.toString()
          }

          return hours.toString().padStart(2, '0') + ':00'
        }
        return value
      },

      // Bytes formatter
      'bytes': (value) => {
        if (typeof value !== 'number') return value

        const units = ['B', 'KB', 'MB', 'GB', 'TB']
        let size = value
        let unitIndex = 0

        while (size >= 1024 && unitIndex < units.length - 1) {
          size /= 1024
          unitIndex++
        }

        return size.toFixed(2) + ' ' + units[unitIndex]
      }
    }

    // IMPORTANT: Check for SPECIFIC patterns FIRST before generic keyword matching
    // The order matters! More specific patterns should be checked before generic ones.

    // Check for specific function calls that uniquely identify the formatter type
    if (formatterString.includes('getHours')) {
      return SAFE_FORMATTERS.time
    }

    if (formatterString.includes('toLocaleDateString')) {
      return SAFE_FORMATTERS.date
    }

    if (formatterString.includes('toLocaleTimeString')) {
      return SAFE_FORMATTERS.time
    }

    if (formatterString.includes('toLocaleString')) {
      return SAFE_FORMATTERS.number_delimited
    }

    if (formatterString.includes('toFixed(2)') && formatterString.includes('ms')) {
      return SAFE_FORMATTERS.duration_ms
    }

    // Try to match the formatter string to a known safe pattern by key name
    // This is less specific and should come after the function call checks above
    for (const [key, formatter] of Object.entries(SAFE_FORMATTERS)) {
      if (formatterString.includes(key) ||
          formatterString.includes(key.replace('_', ''))) {
        return formatter
      }
    }

    // Default: return a safe identity function that just returns the value
    console.warn('[RailsPulse] Unknown formatter pattern, using identity function:', formatterString.substring(0, 100))
    return (value) => value
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

  // Series toggle — dispatched from series_toggle_controller
  // Toggles all series whose name starts with seriesName (e.g. "P95" matches "P95" and "P95 SLO (200ms)")
  onSeriesToggle({ detail: { chartId, seriesName } }) {
    if (chartId !== this.element.id || !this.chart) return

    const allNames = (this.dataValue?.series || []).map(s => s.name).filter(Boolean)
    const matches = allNames.filter(name => name.startsWith(seriesName))
    const namesToToggle = matches.length > 0 ? matches : [seriesName]

    namesToToggle.forEach(name => {
      this.chart.dispatchAction({ type: 'legendToggleSelect', name })
    })
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
