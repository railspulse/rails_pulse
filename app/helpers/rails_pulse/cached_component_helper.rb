module RailsPulse
  module CachedComponentHelper
    def cached_component(options)
      cache_key = ComponentCacheKey.build(options[:id], options[:context])

      # Add refresh action for panels if requested
      if options[:refresh_action] && options[:component] == "panel"
        options[:actions] ||= []
        options[:actions] << refresh_action_params(options[:id], options[:context], options[:content_partial])
      end

      if false
        render_cached_content(options)
      else
        render_skeleton_with_frame(options)
      end
    end

    private

    def render_cached_content(options)
      cache_key = ComponentCacheKey.build(options[:id], options[:context])
      cached_data = Rails.cache.read(cache_key)
      @component_data = cached_data[:component_data]
      @cached_at = cached_data[:cached_at]
      component_options = cached_data[:component_options] || {}

      # Wrap the cached content in a Turbo Frame so it can be refreshed using a refresh link in the component
      turbo_frame_tag "#{options[:id]}_#{options[:component]}", class: options[:class] do
        render "rails_pulse/components/#{options[:component]}", component_options
      end
    end

    def render_skeleton_with_frame(options)
      # Store component options temporarily so CachesController can access them
      cache_key = ComponentCacheKey.build(options[:id], options[:context])
      Rails.cache.write(cache_key, component_options: options, expires_in: 5.minutes)
      path_options = options.slice :id, :context

      turbo_frame_tag "#{options[:id]}_#{options[:component]}",
                      src: rails_pulse.cache_path(**path_options),
                      loading: "eager",
                      class: options[:class] do
        render "rails_pulse/skeletons/#{options[:component]}", options
      end
    end

    def refresh_action_params(id, context, content_partial)
      refresh_params = {
        id: id,
        component_type: "panel",
        refresh: true
      }

      # Include content_partial in refresh URL if available
      refresh_params[:content_partial] = content_partial if content_partial

      {
        url: rails_pulse.cache_path(refresh_params),
        icon: "refresh-cw",
        title: "Refresh data",
        data: {
          controller: "rails-pulse--timezone",
          rails_pulse__timezone_target_frame_value: "#{id}_panel",
          rails_pulse__timezone_cached_at_value: Time.current.iso8601,
          turbo_frame: "#{id}_panel",
          turbo_prefetch: "false"
        }
      }
    end
  end
end
