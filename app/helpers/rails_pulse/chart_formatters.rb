module RailsPulse
  module ChartFormatters
    def self.period_as_time_or_date(time_diff_hours)
      if time_diff_hours <= 25
        <<~JS
          function(value) {
            const date = new Date(value * 1000);
            return date.getHours().toString().padStart(2, '0') + ':00';
          }
        JS
      else
        <<~JS
          function(value) {
            const date = new Date(value * 1000);
            return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          }
        JS
      end
    end

    def self.tooltip_as_time_or_date_with_marker(time_diff_hours)
      if time_diff_hours <= 25
        <<~JS
          function(params) {
            const data = params[0];
            const date = new Date(data.axisValue * 1000);
            const dateString = date.getHours().toString().padStart(2, '0') + ':00';
            return `${dateString} <br /> ${data.marker} ${parseInt(data.data)} ms`;
          }
        JS
      else
        <<~JS
          function(params) {
            const data = params[0];
            const date = new Date(data.axisValue * 1000);
            const dateString = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
            return `${dateString} <br /> ${data.marker} ${parseInt(data.data)} ms`;
          }
        JS
      end
    end
  end
end
