module RailsPulse
  module StatusHelper
    def route_status_indicator(status_value)
      case status_value.to_i
      when 0
        # Healthy routes show no icon to reduce visual clutter
        ""
      when 1
        content_tag(
          :span,
          lucide_icon("alert-triangle", width: "16", height: "16", class: "text-yellow-600"),
          title: "Warning - Response time > #{RailsPulse.configuration.route_thresholds[:slow]} ms"
        )
      when 2
        content_tag(
          :span,
          lucide_icon("alert-circle", width: "16", height: "16", class: "text-orange-600"),
          title: "Slow - Response time > #{RailsPulse.configuration.route_thresholds[:very_slow]} ms"
        )
      when 3
        content_tag(
          :span,
          lucide_icon("x-circle", width: "16", height: "16", class: "text-red-600"),
          title: "Critical - Response time > #{RailsPulse.configuration.route_thresholds[:critical]} ms"
        )
      else
        content_tag(
          :span,
          lucide_icon("help-circle", width: "16", height: "16", class: "text-gray-400"),
          title: "Unknown status"
        )
      end
    end

    def request_status_indicator(duration)
      thresholds = RailsPulse.configuration.request_thresholds
      status_value = case duration.to_i
      when 0...thresholds[:slow]
        0 # Healthy
      when thresholds[:slow]...thresholds[:very_slow]
        1 # Warning
      when thresholds[:very_slow]...thresholds[:critical]
        2 # Slow
      else
        3 # Critical
      end

      case status_value
      when 0
        # Healthy requests show no icon to reduce visual clutter
        ""
      when 1
        content_tag(
          :span,
          lucide_icon("alert-triangle", width: "16", height: "16", class: "text-yellow-600"),
          title: "Warning - Response time > #{thresholds[:slow]} ms"
        )
      when 2
        content_tag(
          :span,
          lucide_icon("alert-circle", width: "16", height: "16", class: "text-orange-600"),
          title: "Slow - Response time > #{thresholds[:very_slow]} ms"
        )
      when 3
        content_tag(
          :span,
          lucide_icon("x-circle", width: "16", height: "16", class: "text-red-600"),
          title: "Critical - Response time > #{thresholds[:critical]} ms"
        )
      else
        content_tag(
          :span,
          lucide_icon("help-circle", width: "16", height: "16", class: "text-gray-400"),
          title: "Unknown status"
        )
      end
    end

    def query_status_indicator(avg_duration)
      thresholds = RailsPulse.configuration.query_thresholds
      status_value = case avg_duration.to_f
      when 0...thresholds[:slow]
        0 # Healthy
      when thresholds[:slow]...thresholds[:very_slow]
        1 # Warning
      when thresholds[:very_slow]...thresholds[:critical]
        2 # Slow
      else
        3 # Critical
      end

      case status_value
      when 0
        # Healthy queries show no icon to reduce visual clutter
        ""
      when 1
        content_tag(
          :span,
          lucide_icon("alert-triangle", width: "16", height: "16", class: "text-yellow-600"),
          title: "Warning - Query time > #{thresholds[:slow]} ms"
        )
      when 2
        content_tag(
          :span,
          lucide_icon("alert-circle", width: "16", height: "16", class: "text-orange-600"),
          title: "Slow - Query time > #{thresholds[:very_slow]} ms"
        )
      when 3
        content_tag(
          :span,
          lucide_icon("x-circle", width: "16", height: "16", class: "text-red-600"),
          title: "Critical - Query time > #{thresholds[:critical]} ms"
        )
      else
        content_tag(
          :span,
          lucide_icon("help-circle", width: "16", height: "16", class: "text-gray-400"),
          title: "Unknown status"
        )
      end
    end

    def operation_status_indicator(operation)
      # Define operation-specific thresholds
      thresholds = case operation.operation_type
      when "sql"
        { slow: 50, very_slow: 100, critical: 500 }
      when "template", "partial", "layout", "collection"
        { slow: 50, very_slow: 150, critical: 300 }
      when "controller"
        { slow: 200, very_slow: 500, critical: 1000 }
      when "cache_read", "cache_write"
        { slow: 10, very_slow: 50, critical: 100 }
      when "http"
        { slow: 500, very_slow: 1000, critical: 3000 }
      when "job"
        { slow: 1000, very_slow: 5000, critical: 10000 }
      when "mailer"
        { slow: 500, very_slow: 2000, critical: 5000 }
      when "storage"
        { slow: 500, very_slow: 1000, critical: 3000 }
      else
        { slow: 100, very_slow: 300, critical: 1000 }
      end

      duration = operation.duration.to_f
      status_value = case duration
      when 0...thresholds[:slow]
        0 # Healthy
      when thresholds[:slow]...thresholds[:very_slow]
        1 # Warning
      when thresholds[:very_slow]...thresholds[:critical]
        2 # Slow
      else
        3 # Critical
      end

      case status_value
      when 0
        # Healthy operations show no icon to reduce visual clutter
        ""
      when 1
        content_tag(
          :span,
          lucide_icon("alert-triangle", width: "16", height: "16", class: "text-yellow-600"),
          title: "Warning - Operation time > #{thresholds[:slow]} ms"
        )
      when 2
        content_tag(
          :span,
          lucide_icon("alert-circle", width: "16", height: "16", class: "text-orange-600"),
          title: "Slow - Operation time > #{thresholds[:very_slow]} ms"
        )
      when 3
        content_tag(
          :span,
          lucide_icon("x-circle", width: "16", height: "16", class: "text-red-600"),
          title: "Critical - Operation time > #{thresholds[:critical]} ms"
        )
      else
        content_tag(
          :span,
          lucide_icon("help-circle", width: "16", height: "16", class: "text-gray-400"),
          title: "Unknown status"
        )
      end
    end

    def operations_performance_breakdown(operations)
      return { database: 0, view: 0, application: 0, other: 0 } if operations.empty?

      total_duration = operations.sum(&:duration).to_f
      return { database: 0, view: 0, application: 0, other: 0 } if total_duration.zero?

      breakdown = operations.group_by { |op| categorize_operation(op.operation_type) }
        .transform_values { |ops| ops.sum(&:duration) }

      {
        database: ((breakdown[:database] || 0) / total_duration * 100).round(1),
        view: ((breakdown[:view] || 0) / total_duration * 100).round(1),
        application: ((breakdown[:application] || 0) / total_duration * 100).round(1),
        other: ((breakdown[:other] || 0) / total_duration * 100).round(1)
      }
    end

    def categorize_operation(operation_type)
      case operation_type
      when "sql"
        :database
      when "template", "partial", "layout", "collection"
        :view
      when "controller"
        :application
      else
        :other
      end
    end

    def operation_category_label(operation_type)
      case categorize_operation(operation_type)
      when :database
        "Database"
      when :view
        "View Rendering"
      when :application
        "Application Logic"
      else
        "Other Operations"
      end
    end

    def performance_badge_class(percentile)
      case percentile
      when 0..50
        "badge--positive"
      when 51..75
        "badge--warning"
      when 76..90
        "badge--negative"
      else
        "badge--critical"
      end
    end

    def rescue_template_missing
      yield
      true
    rescue ActionView::MissingTemplate
      false
    end

    def truncate_sql(sql, length: 100)
      return sql if sql.length <= length
      sql.truncate(length)
    end

    def event_color(operation_type)
      case operation_type
      when "sql"
        "#d27d6b"
      when "template", "partial", "layout", "collection"
        "#6c7ab9"
      when "controller"
        "#5ba6b0"
      else
        "#a6a6a6"
      end
    end



    def duration_options(type = :route)
      thresholds = RailsPulse.configuration.public_send("#{type}_thresholds")

      first_label = "All #{type.to_s.humanize.pluralize}"

      [
        [ first_label, :all ],
        [ "Slow (≥ #{thresholds[:slow]}ms)", :slow ],
        [ "Very Slow (≥ #{thresholds[:very_slow]}ms)", :very_slow ],
        [ "Critical (≥ #{thresholds[:critical]}ms)", :critical ]
      ]
    end

    def duration_threshold_filter_options(type = :route)
      thresholds = RailsPulse.configuration.public_send("#{type}_thresholds")

      all_label =
        case type
        when :job then "All Job Runs"
        else "All #{type.to_s.humanize.pluralize}"
        end

      threshold_options = thresholds.map do |name, value|
        [ "#{name.to_s.humanize} (≥ #{value}ms)", value ]
      end.sort_by { |_, value| value }

      [ [ all_label, nil ] ] + threshold_options
    end
  end
end
