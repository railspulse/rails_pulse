module RailsPulse
  module TableHelper
    def render_cell_content(row_data, column)
      value = row_data[column[:field]]

      # Handle links
      if column[:link_to] && row_data[column[:link_to]]
        # Direct link provided
        link_to value, row_data[column[:link_to]], data: { turbo_frame: "_top" }
      elsif column[:link_field] && row_data[column[:link_field]]
        # Generate link based on field type and ID
        case column[:link_field]
        when :query_id
          link_to value, query_path(row_data[column[:link_field]]), data: { turbo_frame: "_top" }
        when :route_id
          link_to value, route_path(row_data[column[:link_field]]), data: { turbo_frame: "_top" }
        else
          value
        end
      elsif column[:format] == :percentage && value.is_a?(Numeric)
        "#{value > 0 ? '+' : ''}#{value}%"
      elsif value.is_a?(Numeric) && column[:field].to_s.include?("time")
        "#{value.round(0)} ms"
      else
        value
      end
    end

    def cell_highlight_class(row_data, column)
      return "" unless column[:highlight]

      case column[:highlight]
      when :trend
        trend = row_data[:trend]
        case trend
        when "worse" then "highlight-red"
        when "better" then "highlight-green"
        else ""
        end
      when :percentage_change
        change = row_data[:percentage_change]
        if change && change > 5
          "highlight-red"
        elsif change && change < -5
          "highlight-green"
        else
          ""
        end
      else
        ""
      end
    end
  end
end
