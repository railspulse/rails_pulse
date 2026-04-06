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

      // Listen for legend toggle events to adjust border radius dynamically
      this.chart.on('legendselectchanged', (params) => {
        this.handleLegendToggle(params)
      })

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
    // Initialize all series as selected (visible) by default
    if (!config.legend) {
      const selected = {}
      if (config.series && Array.isArray(config.series)) {
        config.series.forEach(s => {
          if (s.name) {
            selected[s.name] = true
          }
        })
      }
      config.legend = { show: false, selected: selected }
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

      // Set series data from provided series array, merging any series-level options (e.g. itemStyle)
      const seriesOptions = (config.series && !Array.isArray(config.series)) ? config.series : {}
      config.series = data.series.map((seriesData) => {
        return {
          type: this.typeValue,
          ...seriesOptions,
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
      // Check if it's an ECharts template pattern (e.g., "{value}", "{value} ms")
      if (this.isEChartsTemplate(config.tooltip.formatter)) {
        // Leave ECharts templates as-is
      } else {
        config.tooltip.formatter = this.parseFormatter(config.tooltip.formatter)
      }
    }

    // Process xAxis formatter
    if (config.xAxis?.axisLabel?.formatter && typeof config.xAxis.axisLabel.formatter === 'string') {
      if (!this.isEChartsTemplate(config.xAxis.axisLabel.formatter)) {
        config.xAxis.axisLabel.formatter = this.parseFormatter(config.xAxis.axisLabel.formatter)
      }
    }

    // Process yAxis formatter
    if (config.yAxis?.axisLabel?.formatter && typeof config.yAxis.axisLabel.formatter === 'string') {
      if (!this.isEChartsTemplate(config.yAxis.axisLabel.formatter)) {
        config.yAxis.axisLabel.formatter = this.parseFormatter(config.yAxis.axisLabel.formatter)
      }
    }
  }

  isEChartsTemplate(formatterString) {
    // ECharts template strings use {variableName} patterns
    // Common patterns: {value}, {a}, {b}, {c}, {seriesName}, etc.
    return /^\{[a-zA-Z0-9_]+\}/.test(formatterString.trim()) ||
           formatterString.includes('{value}') ||
           formatterString.includes('{a}') ||
           formatterString.includes('{b}') ||
           formatterString.includes('{c}')
  }

  parseFormatter(formatterString) {
    // Remove function markers if present
    const cleanString = formatterString.replace(/__FUNCTION_START__|__FUNCTION_END__/g, '')

    // Always use safe formatter registry (handles both function strings and keys like "timestamp_to_date")
    return this.getSafeFormatter(cleanString)
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
      },

      // Tooltip formatters (these receive params array, not a single value)
      // Tooltip with time (HH:00) and milliseconds
      'tooltip_time_ms': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        const data = params[0]
        const date = new Date(data.axisValue)
        const dateString = date.getHours().toString().padStart(2, '0') + ':00'
        const value = parseInt(data.data)

        return `${dateString} <br /> ${data.marker} ${value} ms`
      },

      // Tooltip with date (Mon DD) and milliseconds
      'tooltip_date_ms': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        const data = params[0]
        const date = new Date(data.axisValue)
        const dateString = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        const value = parseInt(data.data)

        return `${dateString} <br /> ${data.marker} ${value} ms`
      },

      // Tooltip with time (HH:00) - generic
      'tooltip_time': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        const data = params[0]
        const date = new Date(data.axisValue)
        const dateString = date.getHours().toString().padStart(2, '0') + ':00'

        return `${dateString} <br /> ${data.marker} ${data.data}`
      },

      // Tooltip with date (Mon DD) - generic
      'tooltip_date': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        const data = params[0]
        const date = new Date(data.axisValue)
        const dateString = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })

        return `${dateString} <br /> ${data.marker} ${data.data}`
      },

      // Auto date tooltip - formats timestamp and shows all series
      'auto_date_tooltip': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        // Get the axis value (timestamp) from first series
        const axisValue = params[0].axisValue || params[0].axisValueLabel
        let dateString = axisValue

        // Try to parse as timestamp and format
        if (typeof axisValue === 'number' || (typeof axisValue === 'string' && !isNaN(Number(axisValue)))) {
          const timestamp = Number(axisValue)
          const date = new Date(timestamp)
          if (!isNaN(date.getTime())) {
            dateString = date.toLocaleDateString('en-US', {
              month: 'short',
              day: 'numeric',
              year: date.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined
            })
          }
        }

        // Build tooltip HTML with all series
        let html = `${dateString}<br/>`
        params.forEach(param => {
          const value = typeof param.value === 'number' ? Math.round(param.value) : param.value
          html += `${param.marker} ${param.seriesName}: ${value}<br/>`
        })

        return html
      },

      // Timestamp to date formatter for axis labels
      'timestamp_to_date': (value) => {
        // Try to parse as number if it's a numeric string
        const numValue = typeof value === 'string' ? parseFloat(value) : value

        // If it's a timestamp (number > 1 trillion = after year 2001 in ms), format it
        if (typeof numValue === 'number' && !isNaN(numValue) && numValue > 1000000000000) {
          const date = new Date(numValue)
          if (!isNaN(date.getTime())) {
            return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
          }
        }

        // If it's already a formatted string (like "Mar 30"), return as-is
        return value
      },

      // Tooltip with timestamp formatting
      'tooltip_with_timestamp': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        // Get the axis value (could be timestamp or string)
        const axisValue = params[0].axisValue
        let dateString = axisValue

        // Try to parse as number if it's a numeric string
        const numValue = typeof axisValue === 'string' ? parseFloat(axisValue) : axisValue

        // If it's a timestamp (number > 1 trillion = after year 2001 in ms), format it
        if (typeof numValue === 'number' && !isNaN(numValue) && numValue > 1000000000000) {
          const date = new Date(numValue)
          if (!isNaN(date.getTime())) {
            dateString = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
          }
        }

        // Build tooltip HTML with all series
        let html = `${dateString}<br/>`
        params.forEach(param => {
          const value = typeof param.value === 'number' ? Math.round(param.value) : param.value
          html += `${param.marker} ${param.seriesName}: ${value}<br/>`
        })

        return html
      },

      // Sparkline tooltip - simpler format for small charts
      'sparkline_tooltip': (params) => {
        if (!Array.isArray(params) || params.length === 0) return ''

        const data = params[0]
        let axisValue = data.axisValue
        const value = typeof data.value === 'number' ? Math.round(data.value) : data.value
        const seriesName = data.seriesName || 'Value'

        // Format timestamp as hour if it's a number (timestamp in milliseconds)
        const numValue = typeof axisValue === 'string' ? parseFloat(axisValue) : axisValue
        if (typeof numValue === 'number' && !isNaN(numValue) && numValue > 1000000000000) {
          const date = new Date(numValue)
          if (!isNaN(date.getTime())) {
            // Format as hour (e.g., "08:00")
            axisValue = date.getHours().toString().padStart(2, '0') + ':00'
          }
        }
        // If it's already a formatted string (like "Apr 5"), leave it as-is

        // Show marker, series name, and value (e.g., "● P95: 150")
        return `${axisValue}<br/>${data.marker} ${seriesName}: ${value}`
      }
    }

    // IMPORTANT: Check for SPECIFIC patterns FIRST before generic keyword matching
    // The order matters! More specific patterns should be checked before generic ones.

    // Check for tooltip formatters first (they have params[0], data.axisValue, data.marker)
    const isTooltipFormatter = formatterString.includes('params') &&
                                formatterString.includes('params[0]') &&
                                formatterString.includes('axisValue')

    if (isTooltipFormatter) {
      // Check if it's time-based (has getHours)
      if (formatterString.includes('getHours')) {
        // Check if it formats milliseconds
        if (formatterString.includes('ms')) {
          return SAFE_FORMATTERS.tooltip_time_ms
        }
        return SAFE_FORMATTERS.tooltip_time
      }

      // Check if it's date-based (has toLocaleDateString)
      if (formatterString.includes('toLocaleDateString')) {
        // Check if it formats milliseconds
        if (formatterString.includes('ms')) {
          return SAFE_FORMATTERS.tooltip_date_ms
        }
        return SAFE_FORMATTERS.tooltip_date
      }

      // Default tooltip formatter (shouldn't reach here normally)
      return SAFE_FORMATTERS.tooltip_date
    }

    // Check for axis label formatters (single value parameter)
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

    // Try exact match first
    if (SAFE_FORMATTERS[formatterString]) {
      return SAFE_FORMATTERS[formatterString]
    }

    // Try to match the formatter string to a known safe pattern by key name
    // This is less specific and should come after exact match
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

  // Handle legend toggle to adjust border radius for stacked bars
  handleLegendToggle(params) {
    if (!this.chart) return

    const option = this.chart.getOption()
    const series = option.series || []

    // Only process if we have stacked bar series
    const hasStackedBars = series.some(s => s.type === 'bar' && s.stack)
    if (!hasStackedBars) return

    // Get visibility state from legend
    const selected = params.selected || {}

    // Find visible series (in order)
    const visibleSeriesIndices = []
    series.forEach((s, index) => {
      const isVisible = selected[s.name] !== false
      if (isVisible && s.type === 'bar' && s.stack) {
        visibleSeriesIndices.push(index)
      }
    })

    if (visibleSeriesIndices.length === 0) return

    // Get the topmost visible series (last in the array for stacked bars)
    const topSeriesIndex = visibleSeriesIndices[visibleSeriesIndices.length - 1]

    // Update border radius for each series
    const updatedSeries = series.map((s, index) => {
      if (s.type !== 'bar' || !s.stack) return s

      const isVisible = visibleSeriesIndices.includes(index)
      const isTop = index === topSeriesIndex

      return {
        ...s,
        itemStyle: {
          ...(s.itemStyle || {}),
          borderRadius: (isVisible && isTop) ? [5, 5, 0, 0] : [0, 0, 0, 0]
        }
      }
    })

    // Apply the updated configuration
    this.chart.setOption({ series: updatedSeries })
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
