import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "paginationLimit", "indexTable"]

  static values = {
    chartId: String        // The ID of the chart to be monitored
  }

  // Add properties for improved debouncing
  lastTurboFrameRequestAt = 0;
  pendingRequestTimeout = null;
  pendingRequestData = null;
  selectedColumnIndex = null;
  zrClickHandler = null;
  highlightBarName = '__rp_col_bg__';
  charts = {};          // all chart instances keyed by container ID
  chartSetup = {};      // tracks which charts have been fully set up
  activeChartId = null; // ID of the currently active chart

  connect() {
    // Respect chart_type URL param so the active chart's listeners are set up correctly on load
    const urlParams = new URLSearchParams(window.location.search)
    const chartType = urlParams.get('chart_type')
    const chartTypeMap = {
      response_time: 'response_time_percentiles_chart',
      request_rate: 'request_rate_chart',
      error_rate: 'error_rate_chart',
      query_performance: 'query_performance_chart',
      execution_volume: 'execution_volume_chart',
      database_load: 'database_load_chart'
    }
    this.activeChartId = chartTypeMap[chartType] || this.chartIdValue

    // Listen for the custom event 'stimulus:echarts:rendered' to set up the chart.
    // This event is dispatched by the chart controller when the chart is ready.
    this.handleChartInitialized = this.onChartInitialized.bind(this);

    document.addEventListener('stimulus:echarts:rendered', this.handleChartInitialized);
  }

  disconnect() {
    // Remove the event listener when the controller is disconnected
    document.removeEventListener('stimulus:echarts:rendered', this.handleChartInitialized);

    // Remove chart event listeners if they exist
    const activeContainer = this.getActiveChartContainer()
    if (activeContainer) {
      activeContainer.removeEventListener('mousedown', this.handleChartMouseDown);
      activeContainer.removeEventListener('mouseup', this.handleChartMouseUp);
    }
    document.removeEventListener('mouseup', this.handleDocumentMouseUp);

    // Remove ZRender handlers
    try {
      if (this.chart && this.zrClickHandler) {
        this.chart.getZr().off('click', this.zrClickHandler)
      }
      if (this.chart && this.zrMouseMoveHandler) {
        this.chart.getZr().off('mousemove', this.zrMouseMoveHandler)
      }
    } catch (e) { /* chart may already be disposed */ }

    // Clear any pending timeout
    if (this.pendingRequestTimeout) {
      clearTimeout(this.pendingRequestTimeout);
    }
  }

  // After the chart is initialized, set up the event listeners and data tracking
  onChartInitialized(event) {
    const { containerId, chart } = event.detail

    // Store every chart instance as it renders
    this.charts[containerId] = chart

    // Only fully set up the initially active chart
    if (containerId === this.activeChartId) {
      this.chart = chart;
      this.setup();
    }
  }

  // Called when the chart switcher changes the active chart
  handleChartSwitched(event) {
    const { fromId, toId } = event.detail
    if (!toId || toId === this.activeChartId) return

    // Capture current zoom state before switching
    const zoomState = this.captureZoomState()

    // Tear down listeners from the outgoing chart
    this.teardownActiveChartListeners()

    // Clear cached bar styles so they get re-read from the incoming chart's data.
    // Keep selectedColumnIndex — initializeColumnSelectionFromUrl will resolve the
    // correct index for the new chart from the URL's selected_column_time param.
    this.originalBarItemStyles = null

    // Switch active chart
    this.activeChartId = toId
    this.chart = this.charts[toId]

    if (!this.chart) return // chart not initialized yet (shouldn't happen with zoom: false on hidden charts)

    // Apply the same zoom to the new chart
    if (zoomState) {
      this.applyZoomState(zoomState)
    }

    if (!this.chartSetup[toId]) {
      // First visit — full setup including highlight series and column restore
      this.setup()
    } else {
      // Returning to a previously-set-up chart — re-attach listeners and restore column
      this.visibleData = this.getVisibleData()
      this.setupChartEventListeners()
      this.initializeColumnSelectionFromUrl()
    }
  }

  captureZoomState() {
    if (!this.chart) return null
    try {
      const option = this.chart.getOption()
      const dataZoom = option.dataZoom?.[1] || option.dataZoom?.[0]
      if (!dataZoom) return null
      return { startValue: dataZoom.startValue, endValue: dataZoom.endValue }
    } catch (e) {
      return null
    }
  }

  applyZoomState(zoomState) {
    if (!this.chart || zoomState.startValue === undefined || zoomState.endValue === undefined) return
    try {
      this.chart.dispatchAction({ type: 'dataZoom', startValue: zoomState.startValue, endValue: zoomState.endValue })
      this.visibleData = this.getVisibleData()
    } catch (e) {}
  }

  teardownActiveChartListeners() {
    const container = this.getActiveChartContainer()
    if (container) {
      container.removeEventListener('mousedown', this.handleChartMouseDown)
      container.removeEventListener('mouseup', this.handleChartMouseUp)
    }
    try {
      if (this.chart) {
        this.chart.off('datazoom')
        if (this.zrClickHandler) this.chart.getZr().off('click', this.zrClickHandler)
        if (this.zrMouseMoveHandler) this.chart.getZr().off('mousemove', this.zrMouseMoveHandler)
      }
    } catch (e) {}
    this.zrClickHandler = null
    this.zrMouseMoveHandler = null
  }

  getActiveChartContainer() {
    return this.chartTargets.find(el => el.dataset.chartId === this.activeChartId) || null
  }

  setup() {
    if (this.chartSetup[this.activeChartId]) {
      return; // Prevent multiple setups for the same chart
    }

    // We need both the chart container in DOM and the chart object
    const container = this.getActiveChartContainer()
    if (!container || !this.chart) {
      return;
    }

    this.visibleData = this.getVisibleData();

    // Add the dedicated background-highlight bar series before setting up listeners
    this.setupHighlightSeries();

    this.setupChartEventListeners();
    this.chartSetup[this.activeChartId] = true;

    // Mark the chart as fully rendered for testing
    document.getElementById(this.activeChartId)?.setAttribute('data-chart-rendered', 'true');

    // Initialize zoom and column selection from URL parameters after chart is fully ready
    // This must come AFTER storing the original option to avoid storing modified state
    this.initializeZoomFromUrl();
    this.initializeColumnSelectionFromUrl();
  }

  // Add some event listeners to the chart so we can track the zoom changes
  setupChartEventListeners() {
    const container = this.getActiveChartContainer()

    // When clicking on the chart, we want to store the current visible data so we can compare it later
    this.handleChartMouseDown = () => {
      this.visibleData = this.getVisibleData();
    };
    container.addEventListener('mousedown', this.handleChartMouseDown);

    // When releasing the mouse button, we want to check if the visible data has changed
    this.handleChartMouseUp = () => {
      this.handleZoomChange();
    };
    container.addEventListener('mouseup', this.handleChartMouseUp);

    // When the chart is zoomed, we want to check if the visible data has changed
    this.chart.on('datazoom', () => {
      this.handleZoomChange();
    });

    // When releasing the mouse button outside the chart, we want to check if the visible data has changed
    this.handleDocumentMouseUp = () => {
      this.handleZoomChange();
    };
    document.addEventListener('mouseup', this.handleDocumentMouseUp);

    // Use ZRender (the underlying canvas renderer) to catch clicks anywhere in the
    // chart grid — not just on data point markers — then map the pixel position back
    // to an x-axis category index so any click in a column triggers filtering.
    this.zrClickHandler = (params) => {
      const dataCoord = this.chart.convertFromPixel(
        { seriesIndex: 0 },
        [params.offsetX, params.offsetY]
      )
      if (!dataCoord) return // click was outside the grid area

      const dataIndex = Math.round(dataCoord[0])
      const option = this.chart.getOption()
      if (!option.xAxis?.[0]?.data) return
      if (dataIndex < 0 || dataIndex >= option.xAxis[0].data.length) return

      this.handleColumnClick({ dataIndex })
    }
    this.chart.getZr().on('click', this.zrClickHandler)

    // Show a pointer cursor when hovering over the clickable grid area.
    this.zrMouseMoveHandler = (params) => {
      const dataCoord = this.chart.convertFromPixel(
        { seriesIndex: 0 },
        [params.offsetX, params.offsetY]
      )
      this.chart.getZr().setCursorStyle(dataCoord ? 'pointer' : 'default')
    }
    this.chart.getZr().on('mousemove', this.zrMouseMoveHandler)
  }

  // This returns the visible data from the chart based on the current zoom level.
  // The xAxis data and series data are sliced based on the start and end values of the dataZoom component.
  // The series data will contain the actual data points that are visible in the chart.
  getVisibleData() {
    try {
      const currentOption = this.chart.getOption();

      if (!currentOption.dataZoom || currentOption.dataZoom.length === 0) {
        return { xAxis: [], series: [] };
      }

      // Try to find the correct dataZoom component
      let dataZoom = currentOption.dataZoom[1] || currentOption.dataZoom[0];

      if (!currentOption.xAxis || !currentOption.xAxis[0] || !currentOption.xAxis[0].data) {
        return { xAxis: [], series: [] };
      }

      if (!currentOption.series || !currentOption.series[0] || !currentOption.series[0].data) {
        return { xAxis: [], series: [] };
      }

      const xAxisData = currentOption.xAxis[0].data;
      const seriesData = currentOption.series[0].data;

      const startValue = dataZoom.startValue || 0;
      const endValue = dataZoom.endValue || xAxisData.length - 1;

      return {
        xAxis: xAxisData.slice(startValue, endValue + 1),
        series: seriesData.slice(startValue, endValue + 1)
      };
    } catch (error) {
      return { xAxis: [], series: [] };
    }
  }

  // When the zoom level changes, we want to check if the visible data has changed
  // If it has, we want to send a request to the server with the new visible data so
  // we can update the table with the new data that is visible in the chart.
  handleZoomChange() {
    const newVisibleData = this.getVisibleData();
    const newDataString = newVisibleData.xAxis.join();
    const currentDataString = this.visibleData.xAxis.join();

    if (newDataString !== currentDataString) {
      this.visibleData = newVisibleData;
      this.updateUrlWithZoomParams(newVisibleData);
      this.sendTurboFrameRequest(newVisibleData);
    }
  }

  // Update the browser URL with zoom parameters so they persist on page refresh
  updateUrlWithZoomParams(data) {
    const url = new URL(window.location.href);
    const currentParams = new URLSearchParams(url.search);

    const startTimestamp = data.xAxis[0];
    const endTimestamp = data.xAxis[data.xAxis.length - 1];

    // Update zoom parameters in URL while preserving all other parameters including sort
    currentParams.set('zoom_start_time', startTimestamp);
    currentParams.set('zoom_end_time', endTimestamp);

    url.search = currentParams.toString();
    window.history.replaceState({}, '', url);
  }

  updatePaginationLimit() {
      // Update or set the limit param in the browser so if the user refreshes the page,
      // the limit will be preserved.
      if (!this.hasPaginationLimitTarget) return;

      const url = new URL(window.location.href);
      const currentParams = new URLSearchParams(url.search);
      const limit = this.paginationLimitTarget.value;
      currentParams.set('limit', limit);
      url.search = currentParams.toString();
      window.history.replaceState({}, '', url);
    }

  // Improved debouncing with guaranteed final request
  sendTurboFrameRequest(data) {
    const now = Date.now();
    const timeSinceLastRequest = now - this.lastTurboFrameRequestAt;

    // Store the latest data for potential delayed execution
    this.pendingRequestData = data;

    // Clear any existing timeout
    if (this.pendingRequestTimeout) {
      clearTimeout(this.pendingRequestTimeout);
    }

    // If enough time has passed since last request, execute immediately
    if (timeSinceLastRequest >= 1000) {
      this.executeTurboFrameRequest(data);
    } else {
      // Otherwise, schedule execution for later to ensure final request goes through
      const remainingTime = 1000 - timeSinceLastRequest;
      this.pendingRequestTimeout = setTimeout(() => {
        this.executeTurboFrameRequest(this.pendingRequestData);
        this.pendingRequestTimeout = null;
      }, remainingTime);
    }
  }

  // Execute the actual AJAX request
  executeTurboFrameRequest(data) {
    this.lastTurboFrameRequestAt = Date.now();

    // Start with the current page's URL to preserve all existing parameters including sort
    const url = new URL(window.location.href);

    // Preserve existing URL parameters (including sort parameters like q[s])
    const currentParams = new URLSearchParams(url.search);

    const startTimestamp = data.xAxis[0];
    const endTimestamp = data.xAxis[data.xAxis.length - 1];

    // Add or update the zoom occurred_at parameters for table filtering
    currentParams.set('zoom_start_time', startTimestamp);
    currentParams.set('zoom_end_time', endTimestamp);

    // Set the limit param based on the value in the pagination selector
    if (this.hasPaginationLimitTarget) {
      currentParams.set('limit', this.paginationLimitTarget.value);
    }

    // Update the URL's search parameters
    url.search = currentParams.toString();

    fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html, text/html',
        'Turbo-Frame': this.indexTableTarget.id,
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      return response.text();
    })
    .then(html => {
      // Find the turbo-frame in the document using the target
      const frame = this.indexTableTarget;
      if (frame) {
        // Parse the response HTML
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');

        // Find the turbo-frame in the response using the frame's ID
        const responseFrame = doc.querySelector(`turbo-frame#${frame.id}`);
        if (responseFrame) {
          // CSP-safe content replacement using DOM methods
          this.replaceFrameContent(frame, responseFrame);
        } else {
          // No turbo frame in response (e.g. no data for selected period) — clear the table
          while (frame.firstChild) frame.removeChild(frame.firstChild);
        }
      }
    })
    .catch(error => console.error('[IndexController] Fetch error:', error));
  }

  // CSP-safe method to replace frame content using DOM methods
  replaceFrameContent(targetFrame, sourceFrame) {
    try {
      // Clear existing content using DOM methods
      while (targetFrame.firstChild) {
        targetFrame.removeChild(targetFrame.firstChild);
      }

      // Clone and append all child nodes from source frame
      const children = Array.from(sourceFrame.childNodes);
      children.forEach(child => {
        const clonedChild = child.cloneNode(true);
        targetFrame.appendChild(clonedChild);
      });
    } catch (error) {
      console.error('Error replacing frame content:', error);
      // Fallback to innerHTML as last resort (not ideal for CSP)
      targetFrame.innerHTML = sourceFrame.innerHTML;
    }
  }

  // CSP-safe fallback method for parsing raw HTML
  replaceFrameContentFromHTML(targetFrame, html) {
    try {
      // Parse HTML safely
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');

      // Clear existing content
      while (targetFrame.firstChild) {
        targetFrame.removeChild(targetFrame.firstChild);
      }

      // If the HTML contains a single root element, use its children
      const bodyChildren = Array.from(doc.body.childNodes);
      bodyChildren.forEach(child => {
        const clonedChild = child.cloneNode(true);
        targetFrame.appendChild(clonedChild);
      });
    } catch (error) {
      console.error('Error parsing HTML content:', error);
      // Last resort fallback
      targetFrame.innerHTML = html;
    }
  }

  handleColumnClick(params) {
    const clickedIndex = params.dataIndex;

    // If clicking the same column that's already selected, deselect all
    if (this.selectedColumnIndex === clickedIndex) {
      this.resetColumnColors();
      this.selectedColumnIndex = null;
      this.sendColumnDeselectionRequest();
    } else {
      // Select the clicked column and gray out others
      this.highlightColumn(clickedIndex);
      this.selectedColumnIndex = clickedIndex;
      this.sendColumnSelectionRequest(clickedIndex);
    }
  }

  // Add a bar series on a hidden secondary y-axis (range 0–1) to use as a column
  // background highlight. markArea on a category axis with timestamp data is
  // unreliable — it looks up values rather than treating integers as indices, so a
  // dedicated bar series is the only dependable approach.
  setupHighlightSeries() {
    try {
      const option = this.chart.getOption()

      // Bar charts don't use the highlight overlay series — adding a second bar series
      // causes ECharts to shrink all bars. Bar charts have inherent column distinction.
      const primaryType = option.series?.[0]?.type
      if (primaryType === 'bar') return

      const xAxisLength = option.xAxis?.[0]?.data?.length || 0
      const existingYAxes = Array.isArray(option.yAxis) ? option.yAxis : [option.yAxis || {}]

      this.chart.setOption({
        yAxis: [
          ...existingYAxes,
          // Hidden secondary axis: bar value of 1 = full chart height
          { show: false, position: 'right', min: 0, max: 1 }
        ],
        series: [
          ...(option.series || []),
          {
            name: this.highlightBarName,
            type: 'bar',
            yAxisIndex: existingYAxes.length,
            barWidth: '100%',
            itemStyle: { color: 'rgba(0, 0, 0, 0)', borderWidth: 0 },
            data: Array(xAxisLength).fill(null),
            silent: true,
            z: 0,
            animation: false,
            legendHoverLink: false,
            tooltip: { show: false }
          }
        ]
      })
    } catch (error) {
      console.error('Error setting up highlight series:', error)
    }
  }

  highlightColumn(selectedIndex) {
    try {
      const option = this.chart.getOption()
      const xAxisLength = option.xAxis?.[0]?.data?.length
      if (!xAxisLength || selectedIndex < 0 || selectedIndex >= xAxisLength) return

      const isPrimaryBar = option.series?.[0]?.type === 'bar'

      if (isPrimaryBar) {
        // Cache original item styles before first modification so we can restore colors on reset
        if (!this.originalBarItemStyles) {
          const seriesData = option.series?.[0]?.data || []
          this.originalBarItemStyles = seriesData.map(val =>
            typeof val === 'object' ? (val.itemStyle || {}) : {}
          )
        }

        // For bar charts: dim non-selected bars by updating per-bar itemStyle opacity
        this.chart.setOption({
          series: option.series.slice(0, 1).map(s => ({
            data: (s.data || []).map((val, i) => ({
              value: typeof val === 'object' ? val.value : val,
              itemStyle: { ...(this.originalBarItemStyles[i] || {}), opacity: i === selectedIndex ? 1 : 0.25 }
            }))
          }))
        })
      } else {
        // For line charts: use the hidden background bar series
        const barData = Array(xAxisLength).fill(null)
        barData[selectedIndex] = 1

        this.chart.setOption({
          series: option.series.map(s =>
            s.name === this.highlightBarName
              ? { itemStyle: { color: 'rgba(128, 128, 128, 0.2)', borderWidth: 0 }, data: barData }
              : {}
          )
        })
      }
    } catch (error) {
      console.error('Error highlighting column:', error)
    }
  }

  resetColumnColors() {
    try {
      const option = this.chart.getOption()
      const xAxisLength = option.xAxis?.[0]?.data?.length || 0
      const isPrimaryBar = option.series?.[0]?.type === 'bar'

      if (isPrimaryBar) {
        // Restore full opacity on all bars, preserving original per-bar colors
        const originalStyles = this.originalBarItemStyles || []
        this.originalBarItemStyles = null
        this.chart.setOption({
          series: option.series.slice(0, 1).map(s => ({
            data: (s.data || []).map((val, i) => ({
              value: typeof val === 'object' ? val.value : val,
              itemStyle: { ...(originalStyles[i] || {}), opacity: 1 }
            }))
          }))
        })
      } else {
        this.chart.setOption({
          series: option.series.map(s =>
            s.name === this.highlightBarName
              ? { itemStyle: { color: 'rgba(0, 0, 0, 0)', borderWidth: 0 }, data: Array(xAxisLength).fill(null) }
              : {}
          )
        })
      }
    } catch (error) {
      console.error('Error resetting column highlight:', error)
    }
  }

  sendColumnSelectionRequest(columnIndex) {
    // Get the timestamp for the selected column
    const option = this.chart.getOption();
    const xAxisData = option.xAxis[0].data;
    const selectedTimestamp = xAxisData[columnIndex];

    if (!selectedTimestamp) {
      console.error('Could not find timestamp for column index:', columnIndex);
      return;
    }

    // Build the request URL with column selection parameter, preserving all existing params including sort
    const url = new URL(window.location.href);
    const currentParams = new URLSearchParams(url.search);

    // Keep all existing parameters (including sort like q[s]) and add column selection parameter
    currentParams.set('selected_column_time', selectedTimestamp);

    // Preserve pagination limit
    if (this.hasPaginationLimitTarget) {
      currentParams.set('limit', this.paginationLimitTarget.value);
    }

    url.search = currentParams.toString();

    // Update browser URL to persist column selection
    window.history.replaceState({}, '', url);

    // Send the turbo frame request
    this.executeTurboFrameRequestForColumn(url);
  }

  sendColumnDeselectionRequest() {
    // Build the request URL without column selection parameter, preserving all other params including sort
    const url = new URL(window.location.href);
    const currentParams = new URLSearchParams(url.search);

    // Remove only the column selection parameter, keep all others (including sort like q[s])
    currentParams.delete('selected_column_time');

    // Preserve pagination limit
    if (this.hasPaginationLimitTarget) {
      currentParams.set('limit', this.paginationLimitTarget.value);
    }

    url.search = currentParams.toString();

    // Update browser URL to remove column selection
    window.history.replaceState({}, '', url);

    // Send the turbo frame request to restore default/zoom view
    this.executeTurboFrameRequestForColumn(url);
  }

  executeTurboFrameRequestForColumn(url) {
    fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html, text/html',
        'Turbo-Frame': this.indexTableTarget.id,
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      return response.text();
    })
    .then(html => {
      // Find the turbo-frame in the document using the target
      const frame = this.indexTableTarget;
      if (frame) {
        // Parse the response HTML
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');

        // Find the turbo-frame in the response using the frame's ID
        const responseFrame = doc.querySelector(`turbo-frame#${frame.id}`);
        if (responseFrame) {
          // CSP-safe content replacement using DOM methods
          this.replaceFrameContent(frame, responseFrame);
        } else {
          // No turbo frame in response (e.g. no data for selected period) — clear the table
          while (frame.firstChild) frame.removeChild(frame.firstChild);
        }
      }
    })
    .catch(error => console.error('[IndexController] Column selection fetch error:', error));
  }

  initializeZoomFromUrl() {
    const urlParams = new URLSearchParams(window.location.search)
    const zoomStartTime = urlParams.get('zoom_start_time')
    const zoomEndTime = urlParams.get('zoom_end_time')
    if (!zoomStartTime || !zoomEndTime) return

    const option = this.chart.getOption()
    if (!option.xAxis?.[0]?.data) return

    const xAxisData = option.xAxis[0].data
    const startMs = parseInt(zoomStartTime)
    const endMs = parseInt(zoomEndTime)

    const startIndex = xAxisData.reduce((best, ts, i) =>
      Math.abs(parseInt(ts) - startMs) < Math.abs(parseInt(xAxisData[best]) - startMs) ? i : best, 0)
    const endIndex = xAxisData.reduce((best, ts, i) =>
      Math.abs(parseInt(ts) - endMs) < Math.abs(parseInt(xAxisData[best]) - endMs) ? i : best, 0)

    this.chart.dispatchAction({ type: 'dataZoom', startValue: startIndex, endValue: endIndex })
    this.visibleData = this.getVisibleData()
  }

  initializeColumnSelectionFromUrl() {
    // Check if there's a selected_column_time parameter in the URL
    const urlParams = new URLSearchParams(window.location.search);
    const selectedColumnTime = urlParams.get('selected_column_time');

    if (selectedColumnTime) {
      // Find the column index that matches this timestamp
      const option = this.chart.getOption();
      if (!option.xAxis || !option.xAxis[0] || !option.xAxis[0].data) {
        return;
      }

      const xAxisData = option.xAxis[0].data;

      // Try exact match first
      let columnIndex = xAxisData.findIndex(timestamp => timestamp.toString() === selectedColumnTime);

      // If no exact match, try converting to numbers and comparing
      if (columnIndex === -1) {
        const selectedTimeNumber = parseInt(selectedColumnTime);
        columnIndex = xAxisData.findIndex(timestamp => parseInt(timestamp) === selectedTimeNumber);
      }

      if (columnIndex !== -1) {
        // Set the selected column index and apply visual styling
        this.selectedColumnIndex = columnIndex;
        // Use requestAnimationFrame to ensure ECharts is ready
        requestAnimationFrame(() => {
          this.highlightColumn(columnIndex);
        });
      }
    }
  }
}
