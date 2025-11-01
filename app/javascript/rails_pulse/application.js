import * as echarts from "echarts";
import "./theme";
import * as Turbo from "@hotwired/turbo";
import { Application } from "@hotwired/stimulus";

// CSS Zero Controllers
import ContextMenuController from "./controllers/context_menu_controller";
import DatePickerController from "./controllers/datepicker_controller";
import DialogController from "./controllers/dialog_controller";
import MenuController from "./controllers/menu_controller";
import PopoverController from "./controllers/popover_controller";
import FormController from "./controllers/form_controller";

// Rails Pulse Controllers
import ChartController from "./controllers/chart_controller";
import IndexController from "./controllers/index_controller";
import ColorSchemeController from "./controllers/color_scheme_controller";
import PaginationController from "./controllers/pagination_controller";
import TimezoneController from "./controllers/timezone_controller";
import IconController from "./controllers/icon_controller";
import ExpandableRowsController from "./controllers/expandable_rows_controller";
import CollapsibleController from "./controllers/collapsible_controller";
import TableSortController from "./controllers/table_sort_controller";
import GlobalFiltersController from "./controllers/global_filters_controller";
import CustomRangeController from "./controllers/custom_range_controller";

const application = Application.start();

// Configure Stimulus application
application.debug = false;
window.Stimulus = application;

// Make ECharts available globally for chart rendering
window.echarts = echarts;

// Make Turbo available globally
window.Turbo = Turbo;

application.register("rails-pulse--context-menu", ContextMenuController);
application.register("rails-pulse--datepicker", DatePickerController);
application.register("rails-pulse--dialog", DialogController);
application.register("rails-pulse--menu", MenuController);
application.register("rails-pulse--popover", PopoverController);
application.register("rails-pulse--form", FormController);

application.register("rails-pulse--chart", ChartController);
application.register("rails-pulse--index", IndexController);
application.register("rails-pulse--color-scheme", ColorSchemeController);
application.register("rails-pulse--pagination", PaginationController);
application.register("rails-pulse--timezone", TimezoneController);
application.register("rails-pulse--icon", IconController);
application.register("rails-pulse--expandable-rows", ExpandableRowsController);
application.register("rails-pulse--collapsible", CollapsibleController);
application.register("rails-pulse--table-sort", TableSortController);
application.register("rails-pulse--global-filters", GlobalFiltersController);
application.register("rails-pulse--custom-range", CustomRangeController);

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

// Export for global access
window.RailsPulse = {
  application,
  version: "1.0.0"
};
