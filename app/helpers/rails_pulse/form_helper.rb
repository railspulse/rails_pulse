module RailsPulse
  module FormHelper
    # Renders a time range selector that can switch between preset ranges and a custom datetime picker
    #
    # @param form [ActionView::Helpers::FormBuilder] The form builder instance
    # @param time_range_options [Array] Array of [label, value] pairs for the select options
    # @param selected_time_range [Symbol, String] Currently selected time range
    # @return [String] HTML for the time range selector
    def time_range_selector(form, time_range_options:, selected_time_range:)
      global_filters = session_global_filters
      has_global_date_range = global_filters["start_time"].present? && global_filters["end_time"].present?
      global_date_range = has_global_date_range ? "#{global_filters["start_time"]} to #{global_filters["end_time"]}" : ""
      show_custom_picker = selected_time_range.to_sym == :custom
      custom_date_value = params.dig(:q, :custom_date_range) || (show_custom_picker && has_global_date_range ? global_date_range : "")

      content_tag(:div, class: "time-range-selector") do
        concat time_range_select_wrapper(form, time_range_options, selected_time_range)
        concat time_range_picker_wrapper(form, custom_date_value)
      end
    end

    private

    def time_range_select_wrapper(form, time_range_options, selected_time_range)
      content_tag(:div, data: { rails_pulse__custom_range_target: "selectWrapper" }, style: "min-width: 150px;") do
        form.select :period_start_range,
          time_range_options,
          { selected: selected_time_range },
          {
            class: "input",
            data: {
              action: "change->rails-pulse--custom-range#handleChange"
            }
          }
      end
    end

    def time_range_picker_wrapper(form, custom_date_value)
      content_tag(:div,
        data: { rails_pulse__custom_range_target: "pickerWrapper" },
        style: "display: none; position: relative; min-width: 360px;"
      ) do
        concat time_range_picker_input(form, custom_date_value)
        concat time_range_close_button
      end
    end

    def time_range_picker_input(form, custom_date_value)
      form.text_field :custom_date_range,
        value: custom_date_value,
        placeholder: "Pick date range",
        class: "input",
        style: "padding-inline-end: 2.5rem;",
        data: {
          controller: "rails-pulse--datepicker",
          rails_pulse__datepicker_mode_value: "range",
          rails_pulse__datepicker_show_months_value: 2,
          rails_pulse__datepicker_type_value: "datetime"
        }
    end

    def time_range_close_button
      button_tag(
        rails_pulse_icon("x", width: "18"),
        type: "button",
        class: "btn btn--borderless",
        style: "position: absolute; inset-inline-end: 0; inset-block-start: 0; inset-block-end: 0; padding: 0.5rem; background: transparent; border: none;",
        data: { action: "click->rails-pulse--custom-range#showSelect" },
        aria: { label: "Close custom range" }
      )
    end
  end
end
