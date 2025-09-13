import * as echarts from "echarts";
import "./theme";
import * as Turbo from "@hotwired/turbo";
import { Application } from "@hotwired/stimulus";

// CSS Zero Controllers
import ContextMenuController from "./controllers/context_menu_controller";
import DialogController from "./controllers/dialog_controller";
import MenuController from "./controllers/menu_controller";
import PopoverController from "./controllers/popover_controller";
import FormController from "./controllers/form_controller";

// Rails Pulse Controllers
import IndexController from "./controllers/index_controller";
import ColorSchemeController from "./controllers/color_scheme_controller";
import PaginationController from "./controllers/pagination_controller";
import TimezoneController from "./controllers/timezone_controller";
import IconController from "./controllers/icon_controller";
import ExpandableRowsController from "./controllers/expandable_rows_controller";
import CollapsibleController from "./controllers/collapsible_controller";
import TableSortController from "./controllers/table_sort_controller";

const application = Application.start();

// Configure Stimulus application
application.debug = false;
window.Stimulus = application;

// Make ECharts available globally for rails_charts gem
window.echarts = echarts;

// Make Turbo available globally
window.Turbo = Turbo;

application.register("rails-pulse--context-menu", ContextMenuController);
application.register("rails-pulse--dialog", DialogController);
application.register("rails-pulse--menu", MenuController);
application.register("rails-pulse--popover", PopoverController);
application.register("rails-pulse--form", FormController);

application.register("rails-pulse--index", IndexController);
application.register("rails-pulse--color-scheme", ColorSchemeController);
application.register("rails-pulse--pagination", PaginationController);
application.register("rails-pulse--timezone", TimezoneController);
application.register("rails-pulse--icon", IconController);
application.register("rails-pulse--expandable-rows", ExpandableRowsController);
application.register("rails-pulse--collapsible", CollapsibleController);
application.register("rails-pulse--table-sort", TableSortController);

// Ensure Turbo Frames are loaded after page load
document.addEventListener('DOMContentLoaded', () => {
  // Force Turbo to process any frames with src attributes
  const frames = document.querySelectorAll('turbo-frame[src]:not([complete])');
  frames.forEach(frame => {
    // Trigger frame loading by temporarily removing and re-adding src
    const src = frame.getAttribute('src');
    if (src) {
      frame.removeAttribute('src');
      setTimeout(() => frame.setAttribute('src', src), 10);
    }
  });
});

// Also handle frames that are added dynamically
const observer = new MutationObserver((mutations) => {
  mutations.forEach((mutation) => {
    if (mutation.type === 'childList') {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === 1 && node.tagName === 'TURBO-FRAME' && node.hasAttribute('src') && !node.hasAttribute('complete')) {
          const src = node.getAttribute('src');
          if (src) {
            node.removeAttribute('src');
            setTimeout(() => node.setAttribute('src', src), 10);
          }
        }
      });
    }
  });
});

observer.observe(document.body, { childList: true, subtree: true });

// Register ECharts theme for Rails Pulse
echarts.registerTheme('railspulse', {
  "color": ["#ffc91f", "#ffde66", "#fbedbf"],
  "backgroundColor": "rgba(255,255,255,0)",
  "textStyle": {},
  "title": { "textStyle": { "color": "#666666" } },
  "line": { "lineStyle": { "width": "3" }, "symbolSize": "8" },
  "bar": { "itemStyle": { "barBorderWidth": 0 } }
});

// Chart resize functionality (moved from inline script for CSP compliance)
window.addEventListener('resize', function() {
  if (window.RailsCharts && window.RailsCharts.charts) {
    Object.keys(window.RailsCharts.charts).forEach(function(chartID) {
      window.RailsCharts.charts[chartID].resize();
    });
  }
});

// Apply axis label colors based on current color scheme
function applyChartAxisLabelColors() {
  if (!window.RailsCharts || !window.RailsCharts.charts) return;
  const scheme = document.documentElement.getAttribute('data-color-scheme');
  const isDark = scheme === 'dark';
  const axisColor = isDark ? '#ffffff' : '#999999';
  Object.keys(window.RailsCharts.charts).forEach(function(chartID) {
    const chart = window.RailsCharts.charts[chartID];
    try {
      chart.setOption({
        xAxis: { axisLabel: { color: axisColor } },
        yAxis: { axisLabel: { color: axisColor } }
      });
    } catch (e) {
      // noop
    }
  });
}

// Initial apply after charts initialize and on scheme changes
document.addEventListener('DOMContentLoaded', () => {
  // run shortly after load to allow charts to initialize
  setTimeout(applyChartAxisLabelColors, 50);
});
document.addEventListener('rails-pulse:color-scheme-changed', applyChartAxisLabelColors);

// Global function to initialize Rails Charts in any container.
// This is needed as we render Rails Charts in Turbo Frames.
window.initializeChartsInContainer = function(containerId) {
  requestAnimationFrame(() => {
    const container = containerId ? document.getElementById(containerId) : document;
    const scripts = container.querySelectorAll('script');
    scripts.forEach(script => {
      const content = script.textContent;
      const match = content.match(/function\s+(init_rails_charts_[a-f0-9]+)/);
      if (match && window[match[1]]) {
        window[match[1]]();
      }
    });
    // ensure colors are correct for any charts initialized in this container
    setTimeout(applyChartAxisLabelColors, 10);
  });
};

// Export for global access
window.RailsPulse = {
  application,
  version: "1.0.0"
};
