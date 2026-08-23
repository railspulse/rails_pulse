module RailsPulse
  class RoutePathNormalizer
    SKIP_PARAMS = %i[controller action format].freeze

    def self.normalize(path, path_params)
      new(path, path_params).normalize
    end

    def initialize(path, path_params)
      @path = path
      @path_params = path_params || {}
    end

    def normalize
      return @path if @path.nil? || @path.empty?
      return @path if route_params.empty?

      value_to_keys = build_value_map
      segments = @path.split("/", -1)
      segments.map { |seg| substitute_segment(seg, value_to_keys) }.join("/")
    end

    private

    def route_params
      @route_params ||= @path_params.reject { |k, _| SKIP_PARAMS.include?(k) }
    end

    def build_value_map
      route_params.each_with_object({}) do |(key, value), map|
        str = value.to_s
        map[str] ||= []
        map[str] << key
      end
    end

    def substitute_segment(segment, value_to_keys)
      # Exact match — only substitute if unambiguous (one key for this value)
      if (keys = value_to_keys[segment]) && keys.length == 1
        return ":#{keys.first}"
      end

      # Format extension match: e.g. "42.json" when id="42"
      if segment.include?(".")
        base, ext = segment.split(".", 2)
        if (keys = value_to_keys[base]) && keys.length == 1
          return ":#{keys.first}.#{ext}"
        end
      end

      segment
    end
  end
end
