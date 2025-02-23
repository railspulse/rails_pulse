import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart"];

  connect() {
    if (
      document.documentElement.hasAttribute("data-turbolinks-preview") ||
      document.documentElement.hasAttribute("data-turbo-preview")
    ) {
      return;
    }

    if (this.hasChartTarget) {
      try {
        const options = JSON.parse(this.data.get("options"));
        this.chart = window.echarts.init(this.chartTarget, "gray", {
          locale: null,
          renderer: "canvas"
        });
        this.chart.setOption(options);
        window.x = this.chart;
        window.addEventListener("resize", this.resizeChart);
      } catch (error) {
        console.error("Error initializing ECharts:", error);
      }
    }
  }

  disconnect() {
    if (this.chart) {
      this.chart.dispose();
      this.chart = null;
    }
    window.removeEventListener("resize", this.resizeChart);
  }

  resizeChart = () => {
    if (this.chart) {
      this.chart.resize();
    }
  };
}
