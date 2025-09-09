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

  connect() {
    // Listen for the custom event 'chart:initialized' to set up the chart.
    // This event is sent from the RailsCharts library when the chart is ready.
    this.handleChartInitialized = this.onChartInitialized.bind(this);

    document.addEventListener('chart:rendered', this.handleChartInitialized);

    // If the chart is already initialized (e.g., on back navigation), set up immediately
    if (window.RailsCharts?.charts?.[this.chartIdValue]) {
      this.setup();
    }
  }

  disconnect() {
    // Remove the event listener from RailsCharts when the controller is disconnected
    document.removeEventListener('chart:rendered', this.handleChartInitialized);

    // Remove chart event listeners if they exist
    if (this.hasChartTarget && this.chartTarget) {
      this.chartTarget.removeEventListener('mousedown', this.handleChartMouseDown);
      this.chartTarget.removeEventListener('mouseup', this.handleChartMouseUp);
    }
    document.removeEventListener('mouseup', this.handleDocumentMouseUp);

    // Clear any pending timeout
    if (this.pendingRequestTimeout) {
      clearTimeout(this.pendingRequestTimeout);
    }
  }

  // After the chart is initialized, set up the event listeners and data tracking
  onChartInitialized(event) {
    if (event.detail.containerId === this.chartIdValue) {
      this.setup();
    }
  }

  setup() {
    if (this.setupDone) {
      return; // Prevent multiple setups
    }

    // We need both the chart target in DOM and the chart object from RailsCharts
    let hasTarget = false;
    try {
      hasTarget = !!this.chartTarget;
    } catch (e) {
      hasTarget = false;
    }
    
    // Get the chart element which the RailsCharts library has created
    this.chart = window.RailsCharts.charts[this.chartIdValue];
    
    // Only proceed if we have BOTH the DOM target and the chart object
    if (!hasTarget || !this.chart) {
      return;
    }

    this.visibleData = this.getVisibleData();
    this.setupChartEventListeners();
    this.setupDone = true;

    // Mark the chart as fully rendered for testing
    if (hasTarget) {
      document.getElementById(this.chartIdValue)?.setAttribute('data-chart-rendered', 'true');
    }
  }

  // Add some event listeners to the chart so we can track the zoom changes
  setupChartEventListeners() {
    // When clicking on the chart, we want to store the current visible data so we can compare it later
    this.handleChartMouseDown = () => {
      this.visibleData = this.getVisibleData();
    };
    this.chartTarget.addEventListener('mousedown', this.handleChartMouseDown);

    // When releasing the mouse button, we want to check if the visible data has changed
    this.handleChartMouseUp = () => {
      this.handleZoomChange();
    };
    this.chartTarget.addEventListener('mouseup', this.handleChartMouseUp);

    // When the chart is zoomed, we want to check if the visible data has changed
    this.chart.on('datazoom', () => {
      this.handleZoomChange();
    });

    // When releasing the mouse button outside the chart, we want to check if the visible data has changed
    this.handleDocumentMouseUp = () => {
      this.handleZoomChange();
    };
    document.addEventListener('mouseup', this.handleDocumentMouseUp);
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

    // Update zoom parameters in URL
    currentParams.set('zoom_start_time', startTimestamp);
    currentParams.set('zoom_end_time', endTimestamp);

    url.search = currentParams.toString();
    window.history.replaceState({}, '', url);
  }

  updatePaginationLimit() {
      // Update or set the limit param in the browser so if the user refreshes the page,
      // the limit will be preserved.
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

    // Start with the current page's URL
    const url = new URL(window.location.href);

    // Preserve existing URL parameters
    const currentParams = new URLSearchParams(url.search);

    const startTimestamp = data.xAxis[0];
    const endTimestamp = data.xAxis[data.xAxis.length - 1];

    // Add or update the zoom occurred_at parameters for table filtering
    currentParams.set('zoom_start_time', startTimestamp);
    currentParams.set('zoom_end_time', endTimestamp);

    // Set the limit param based on the value in the pagination selector
    url.searchParams.set('limit', this.paginationLimitTarget.value);

    // Update the URL's search parameters
    url.search = currentParams.toString();

    fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'text/html; turbo-frame',
        'Turbo-Frame': this.chartIdValue
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
          // Fallback: parse the entire HTML response
          this.replaceFrameContentFromHTML(frame, html);
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
}
