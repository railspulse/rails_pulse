# Stimulus ECharts Usage Guide

## Overview

Rails Pulse uses a Stimulus controller architecture for chart rendering with Apache ECharts. This provides a clean, modular, CSP-compliant approach with zero inline scripts.

## Basic Usage

### In Views

```erb
<%# Bar chart %>
<%= render_stimulus_chart(@chart_data,
  type: 'bar',
  height: "400px",
  options: bar_chart_options(units: "ms")
) %>

<%# Line chart %>
<%= render_stimulus_chart(@chart_data,
  type: 'line',
  height: "300px",
  options: line_chart_options(units: "requests")
) %>

<%# Sparkline (compact bar chart) %>
<%= render_stimulus_chart(@sparkline_data,
  type: 'bar',
  height: "60px",
  width: "200px",
  options: sparkline_chart_options
) %>

<%# Area chart %>
<%= render_stimulus_chart(@chart_data,
  type: 'area',
  height: "350px",
  options: area_chart_options
) %>
```

### Chart Data Format

Chart data should be a hash with timestamps/labels as keys and values:

```ruby
# Simple format
chart_data = {
  1234567890 => 150.5,
  1234567900 => 200.3,
  1234567910 => 175.8
}

# Object format (for additional metadata)
chart_data = {
  1234567890 => { value: 150.5, name: "Point 1" },
  1234567900 => { value: 200.3, name: "Point 2" }
}
```

### Generated HTML

The helper generates a Stimulus-compatible div with data attributes:

```html
<div id="rails-pulse-chart-abc123"
     style="height: 400px; width: 100%;"
     data-controller="rails-pulse--chart"
     data-rails-pulse--chart-type-value="bar"
     data-rails-pulse--chart-data-value='{"100":1,"200":2}'
     data-rails-pulse--chart-options-value='{"tooltip":...}'
     data-rails-pulse--chart-theme-value="railspulse">
</div>
```

## Chart Options

### Bar Chart Options

```ruby
options = bar_chart_options(
  units: "ms",              # Y-axis unit label
  zoom: true,               # Enable zoom slider
  zoom_start: timestamp1,   # Initial zoom start (optional)
  zoom_end: timestamp2,     # Initial zoom end (optional)
  chart_data: @data,        # Required if using zoom_start/zoom_end
  xaxis_formatter: js_func, # Custom X-axis label formatter
  tooltip_formatter: js_func # Custom tooltip formatter
)
```

### Line Chart Options

```ruby
options = line_chart_options(
  units: "requests",
  zoom: true,
  xaxis_formatter: custom_formatter,
  tooltip_formatter: custom_formatter
)
```

### Sparkline Options

Compact charts with minimal styling:

```ruby
options = sparkline_chart_options  # No parameters needed
```

### Area Chart Options

```ruby
options = area_chart_options  # Uses default settings
```

## Custom Formatters

Formatters are JavaScript functions for customizing chart display:

### Tooltip Formatter

```ruby
tooltip_formatter = <<~JS
  function(params) {
    return params.seriesName + ': ' + params.value + 'ms';
  }
JS

options = bar_chart_options(tooltip_formatter: tooltip_formatter)
```

### X-Axis Formatter

```ruby
xaxis_formatter = <<~JS
  function(value) {
    return new Date(value * 1000).toLocaleDateString();
  }
JS

options = bar_chart_options(xaxis_formatter: xaxis_formatter)
```

**Note:** Formatters use `eval()` for flexibility. For strict CSP environments, consider using predefined formatters or a formatter registry.

## Dynamic Updates

Charts can be updated dynamically via Stimulus actions:

```javascript
// Get chart element
const chartElement = document.getElementById('rails-pulse-chart-abc123')

// Dispatch update event
chartElement.dispatchEvent(new CustomEvent('update', {
  detail: {
    data: { 100: 5, 200: 10 },
    options: { /* new options */ }
  }
}))
```

## Stimulus Controller API

### Values

- `type` (String): Chart type - "bar", "line", "area", or "sparkline"
- `data` (Object): Chart data as JSON
- `options` (Object): ECharts configuration options
- `theme` (String): ECharts theme name (default: "railspulse")

### Targets

None - the controller manages the chart instance directly on its element.

### Actions

- `update`: Update chart data/options dynamically

### Public Methods

- `chartInstance`: Access the underlying ECharts instance

```javascript
const controller = application.getControllerForElementAndIdentifier(
  element,
  'rails-pulse--chart'
)
const echartsInstance = controller.chartInstance
```

## Event-Based Communication

Charts dispatch custom events for inter-controller communication:

### stimulus:echarts:rendered

Dispatched when a chart finishes initialization:

```javascript
document.addEventListener('stimulus:echarts:rendered', (event) => {
  console.log('Chart rendered:', event.detail.containerId)
  console.log('Chart instance:', event.detail.chart)
  console.log('Controller:', event.detail.controller)
})
```

### rails-pulse:color-scheme-changed

Charts automatically update axis colors when color scheme changes. This event is handled internally by the chart controller.

## Turbo Integration

Charts work seamlessly with Turbo navigation:

### Automatic Lifecycle Management

- **Connect**: Chart initializes when element is added to DOM
- **Disconnect**: Chart disposes when element is removed
- **Turbo Frame**: Charts work in Turbo Frames
- **Turbo Stream**: Charts update with Turbo Streams

### Memory Management

The Stimulus controller automatically:
- Disposes charts on disconnect
- Disconnects ResizeObserver
- Removes event listeners

### Best Practices

1. Use Turbo Frame IDs consistently
2. Let Stimulus manage chart lifecycle
3. Avoid manual chart instance storage

## Responsive Design

Charts automatically resize using ResizeObserver:

```javascript
// Automatic - no configuration needed
this.resizeObserver = new ResizeObserver(() => {
  if (this.chart) {
    this.chart.resize()
  }
})
```

## Color Scheme Management

Charts self-manage color scheme updates:

```javascript
// Automatic - listens for scheme changes
document.addEventListener('rails-pulse:color-scheme-changed', () => {
  this.applyColorScheme()
})
```

Axis label colors automatically update for light/dark mode:
- Light mode: `#999999`
- Dark mode: `#ffffff`

## CSP Requirements

### Current Implementation

- ✅ No inline scripts
- ✅ External JS files only
- ✅ Data passed via data attributes
- ⚠️ `eval()` used for formatter functions

### Recommended CSP Headers

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self';
  style-src 'self';
  img-src 'self' data:;
  connect-src 'self';
```

### Formatter Alternatives

If `eval()` is not acceptable in your CSP policy:

#### Option 1: Predefined Formatters

```ruby
# In chart_helper.rb
PREDEFINED_FORMATTERS = {
  date: "function(v) { return new Date(v*1000).toLocaleDateString(); }",
  time: "function(v) { return new Date(v*1000).toLocaleTimeString(); }",
  currency: "function(v) { return '$' + v.toFixed(2); }"
}

options = bar_chart_options(
  tooltip_formatter: PREDEFINED_FORMATTERS[:currency]
)
```

#### Option 2: Formatter Registry

Register formatters in `application.js`:

```javascript
window.RailsPulse.formatters = {
  dateFormatter: function(value) {
    return new Date(value * 1000).toLocaleDateString()
  }
}
```

Then reference by name in options.

#### Option 3: Accept eval() with Documentation

Document the CSP limitation and accept `eval()` for flexibility. This is the current approach.

## Testing

### Helper Tests

```ruby
test "render_stimulus_chart generates Stimulus-compatible div" do
  data = { 100 => 1, 200 => 2 }
  html = render_stimulus_chart(data, type: 'bar', height: "300px")

  assert_match /data-controller="rails-pulse--chart"/, html
  assert_match /data-rails-pulse--chart-type-value="bar"/, html
end
```

### System Tests

```ruby
test "chart renders using Stimulus" do
  visit dashboard_path

  # Wait for chart to render
  assert_selector "[data-chart-rendered='true']", wait: 10

  # Verify no inline scripts
  assert_no_selector "script:not([src])", text: /echarts\.init/
end
```

Use helpers from `test/support/chart_validation_helpers.rb`:

```ruby
include ChartValidationHelpers

test "validates chart data" do
  visit dashboard_path
  assert_chart_rendered("dashboard_chart")
  assert_no_inline_scripts
  validate_chart_data("#dashboard_chart")
end
```

## Troubleshooting

### Chart Not Rendering

1. **Check ECharts loaded**: Open console, type `echarts`
2. **Check Stimulus controller**: `window.Stimulus.router.modulesByIdentifier`
3. **Check data attribute**: Inspect element for `data-rails-pulse--chart-*`
4. **Check console errors**: Look for initialization errors

### Chart Disappears After Render

1. **Check for duplicate controllers**: Remove `data-controller` from parent divs
2. **Check ResizeObserver**: Ensure container has dimensions
3. **Check Turbo Frame**: Verify frame isn't being replaced

### Formatter Not Working

1. **Check function string**: Must start with `function`
2. **Check markers**: Should have `__FUNCTION_START__` wrapper
3. **Check CSP**: `eval()` may be blocked
4. **Check console**: Look for formatter parsing errors

### Charts Not Updating on Color Scheme Change

1. **Check event dispatch**: `rails-pulse:color-scheme-changed` fired?
2. **Check chart instance**: `controller.chartInstance` exists?
3. **Check color values**: Inspect axis label colors in DevTools

## Advanced Usage

### Custom Themes

```ruby
# Register custom theme in application.js
echarts.registerTheme('custom', {
  color: ['#ff0000', '#00ff00'],
  backgroundColor: '#ffffff'
})

# Use in views
<%= render_stimulus_chart(@data,
  type: 'bar',
  theme: 'custom'
) %>
```

### Multiple Chart Types

```ruby
# Render different chart types with same data
<%= render_stimulus_chart(@data, type: 'bar', id: 'bar-view') %>
<%= render_stimulus_chart(@data, type: 'line', id: 'line-view') %>
```

### Accessing Chart Instance

```javascript
// From another controller
const chartElement = document.getElementById('my-chart')
const controller = this.application.getControllerForElementAndIdentifier(
  chartElement,
  'rails-pulse--chart'
)

if (controller && controller.chartInstance) {
  const option = controller.chartInstance.getOption()
  // Manipulate chart...
}
```

## Migration from Old API

If migrating from `rails_pulse_bar_chart`:

### Before

```erb
<%= rails_pulse_bar_chart(@data, height: "400px", options: bar_chart_options) %>
```

### After

```erb
<%= render_stimulus_chart(@data, type: 'bar', height: "400px", options: bar_chart_options) %>
```

Key changes:
1. Method renamed to `render_stimulus_chart`
2. Explicit `type:` parameter required
3. No more inline scripts
4. Stimulus-based lifecycle management

## Performance

### Initialization Time

- Charts initialize asynchronously
- Retry mechanism: 100 attempts × 50ms = max 5 seconds
- Typical initialization: < 500ms

### Memory Usage

- ResizeObserver: ~1KB per chart
- ECharts instance: ~50-100KB per chart
- Proper cleanup on disconnect prevents leaks

### Optimization Tips

1. Use sparkline options for small charts
2. Limit data points (aggregate server-side)
3. Disable animations for many charts: `animation: false`
4. Use virtual scrolling for large datasets

## Future Enhancements

Planned improvements:

1. **Predefined Formatter Library**: Common formatters without eval()
2. **Chart Interaction Events**: Click, hover, zoom events
3. **Multi-Series Support**: Enhanced API for complex charts
4. **Export Functionality**: Save charts as images
5. **npm Package**: Extract as standalone `stimulus-echarts`

## Support

For issues or questions:

1. Check this documentation
2. Review test examples in `test/system/`
3. Check ECharts documentation: https://echarts.apache.org
4. Open issue on GitHub

## License

This implementation follows the same license as Rails Pulse.
