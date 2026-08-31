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

      if route_params.empty?
        # No path params means the request missed the Rails router (404,
        # middleware short-circuit, mounted Rack app). Bucket dynamic segments
        # to prevent unbounded route cardinality from scanners and bots.
        return bucket_unrecognized_path(@path)
      end

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

    # Replace dynamic-looking segments so scanner paths, bot probes, and
    # arbitrary IDs don't create one route row per distinct URL.
    UUID_RE  = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    SHA_RE   = /\A[0-9a-f]{40}\z/i
    DIGIT_RE = /\A\d+\z/

    def bucket_unrecognized_path(path)
      segments = path.split("/", -1)
      segments.map! do |seg|
        case seg
        when UUID_RE  then ":uuid"
        when SHA_RE   then ":sha"
        when DIGIT_RE then ":id"
        else seg
        end
      end
      segments.join("/")
    end
  end
end
