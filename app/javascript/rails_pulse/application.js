import "echarts"
import "echarts/theme/gray"
import "@hotwired/turbo-rails"

import { Application } from "@hotwired/stimulus";

// CSS Zero Controllers
import ContextMenuController from "rails_pulse/controllers/context_menu_controller";
import DialogController from "rails_pulse/controllers/dialog_controller";
import MenuController from "rails_pulse/controllers/menu_controller";
import PopoverController from "rails_pulse/controllers/popover_controller";
import FormController from "rails_pulse/controllers/form_controller";

// Rails Pulse Controllers
import IndexController from "rails_pulse/controllers/index_controller";
import ColorSchemeController from "rails_pulse/controllers/color_scheme_controller";
import PaginationController from "rails_pulse/controllers/pagination_controller";

const application = Application.start();

application.register("rails-pulse--context-menu", ContextMenuController);
application.register("rails-pulse--dialog", DialogController);
application.register("rails-pulse--menu", MenuController);
application.register("rails-pulse--popover", PopoverController);
application.register("rails-pulse--form", FormController);

application.register("rails-pulse--index", IndexController);
application.register("rails-pulse--color-scheme", ColorSchemeController);
application.register("rails-pulse--pagination", PaginationController);
