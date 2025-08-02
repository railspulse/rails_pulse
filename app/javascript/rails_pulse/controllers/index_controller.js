import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "paginationLimit", "indexTable"] // The chart element to be monitored

  static values = {
    chartId: String        // The ID of the chart to be monitored
  }

  // Add a property to track the last request time
  lastTurboFrameRequestAt = 0;

  connect() {
    // Listen for the custom event 'chart:initialized' to set up the chart.
    // This event is sent from the RailsCharts library when the chart is ready.
    this.handleChartInitialized = this.onChartInitialized.bind(this);
    document.addEventListener('chart:initialized', this.handleChartInitialized);

    // If the chart is already initialized (e.g., on back navigation), set up immediately
    if (window.RailsCharts?.charts?.[this.chartIdValue]) { this.setup(); }
  }

  disconnect() {
    // Remove the event listener from RailsCharts when the controller is disconnected
    document.removeEventListener('chart:initialized', this.handleChartInitialized);

    // Remove chart event listeners if they exist
    if (this.chartTarget) {
      this.chartTarget.removeEventListener('mousedown', this.handleChartMouseDown);
      this.chartTarget.removeEventListener('mouseup', this.handleChartMouseUp);
    }
    document.removeEventListener('mouseup', this.handleDocumentMouseUp);
  }

  // After the chart is initialized, set up the event listeners and data tracking
  onChartInitialized(event) {
    if (event.detail.chartId === this.chartIdValue) { this.setup(); }
  }

  setup() {
    if (this.setupDone) return; // Prevent multiple setups

    // Get the chart element which the RailsCharts library has created
    this.chart = window.RailsCharts.charts[this.chartIdValue];
    if (!this.chart) return;

    this.visibleData = this.getVisibleData();
    this.setupChartEventListeners();
    this.setupDone = true;
  }

  // Add some event listeners to the chart so we can track the zoom changes
  setupChartEventListeners() {
    // When clicking on the chart, we want to store the current visible data so we can compare it later
    this.handleChartMouseDown = () => { this.visibleData = this.getVisibleData(); };
    this.chartTarget.addEventListener('mousedown', this.handleChartMouseDown);

    // When releasing the mouse button, we want to check if the visible data has changed
    this.handleChartMouseUp = () => { this.handleZoomChange(); };
    this.chartTarget.addEventListener('mouseup', this.handleChartMouseUp);

    // When the chart is zoomed, we want to check if the visible data has changed
    this.chart.on('datazoom', () => { this.handleZoomChange(); });

    // When releasing the mouse button outside the chart, we want to check if the visible data has changed
    this.handleDocumentMouseUp = () => { this.handleZoomChange(); };
    document.addEventListener('mouseup', this.handleDocumentMouseUp);
  }

  // This returns the visible data from the chart based on the current zoom level.
  // The xAxis data and series data are sliced based on the start and end values of the dataZoom component.
  // The series data will contain the actual data points that are visible in the chart.
  getVisibleData() {
    const currentOption = this.chart.getOption();
    const dataZoom = currentOption.dataZoom[1];
    const xAxisData = currentOption.xAxis[0].data;
    const seriesData = currentOption.series[0].data;

    const startValue = dataZoom.startValue;
    const endValue = dataZoom.endValue;

    return {
      xAxis: xAxisData.slice(startValue, endValue + 1),
      series: seriesData.slice(startValue, endValue + 1)
    };
  }

  // When the zoom level changes, we want to check if the visible data has changed
  // If it has, we want to send a request to the server with the new visible data so
  // we can update the table with the new data that is visible in the chart.
  handleZoomChange() {
    const newVisibleData = this.getVisibleData();
    if (newVisibleData.xAxis.join() !== this.visibleData.xAxis.join()) {
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

  // After the zoom level changes, we want to send a request to the server with the new visible data.
  // The server will then return the full page HTML with the updated table data wrapped in a turbo-frame.
  // We will then replace the innerHTML of the turbo-frame with the new HTML.
  sendTurboFrameRequest(data) {
    const now = Date.now();
    // If less than 1 second since last request, ignore this call
    if (now - this.lastTurboFrameRequestAt < 1000) { return; }
    this.lastTurboFrameRequestAt = now;

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
    .then(response => response.text()) // Get the raw HTML response
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
    .catch(error => console.error('Error:', error));
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
