module RailsPulse
  module Cloud
    # The path a recognised route is sent to Cloud under: its pattern as
    # written in the host's routes, never a value from a request.
    #
    # The stored path is the request path with each parameter value swapped
    # back for its name, which leaves a value in place when two parameters
    # share it (`/users/5/posts/5`) or when a glob captures several segments
    # (`get "*slug"`). So the stored path is matched against the router's
    # patterns for the same controller action, and the pattern is sent.
    # When no pattern lines up (a route since removed, or one inside a
    # mounted engine), each literal segment that does not look like code is
    # replaced with `*`; a segment without a letter is taken for an ID.
    #
    #   patterns = RoutePattern.new
    #   patterns.path_for("/users/5/posts/5", "posts#show")  # => "/users/:user_id/posts/:id"
    #   patterns.path_for("/docs/getting-started", "pages#show")  # => "/*slug" for `get "*slug"`
    class RoutePattern
      PARAMETER = /\A:[A-Za-z_]\w*(?:\.[A-Za-z0-9]+)?\z/
      # More optional groups than this in one route are not expanded.
      MAX_VARIANTS = 16

      def initialize(routes = Rails.application.routes.routes)
        @routes = routes
      end

      def path_for(path, controller_action)
        stored = segments(path.to_s)
        patterns_for(controller_action).each do |pattern|
          matched = match(pattern, stored)
          return matched if matched
        end
        fallback(stored)
      end

      private

      # { "posts#show" => [["", "posts", ":id"], ...] }, built once per instance.
      def patterns_for(controller_action)
        @patterns ||= @routes.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |route, index|
          controller = route.defaults[:controller]
          action = route.defaults[:action]
          next unless controller && action

          variants(route.path.spec.to_s).each { |spec| index["#{controller}##{action}"] << segments(spec) }
        end
        @patterns.fetch(controller_action.to_s, [])
      end

      # "/posts(/:page)(.:format)" => ["/posts/:page", "/posts"], with any
      # `.:format` dropped because the stored path keeps the extension on its
      # last segment rather than as a separate one.
      def variants(spec)
        spec = spec.gsub("(.:format)", "")
        expanded = [ spec ]
        while (template = expanded.find { |candidate| candidate.include?("(") })
          break if expanded.size > MAX_VARIANTS

          expanded.delete(template)
          expanded.push(*optional_group(template))
        end
        expanded.reject { |candidate| candidate.include?("(") }.uniq
      end

      # The template with its innermost optional group kept and removed.
      def optional_group(template)
        start = template.rindex("(")
        finish = template.index(")", start)
        return [ template.delete("()") ] unless finish

        before = template[0...start]
        after = template[(finish + 1)..]
        [ before + template[(start + 1)...finish] + after, before + after ]
      end

      def segments(path)
        path.split("/", -1)
      end

      def match(pattern, stored)
        result = []
        pattern.each_with_index do |expected, index|
          if expected.start_with?("*")
            return nil if index >= stored.size

            result << expected
            return result.join("/")
          end

          actual = stored[index]
          return nil if actual.nil?
          return nil unless expected == actual || expected.include?(":")

          result << expected
        end

        stored.size == pattern.size ? result.join("/") : nil
      end

      def fallback(stored)
        stored.map do |segment|
          next segment if segment.empty?
          next segment if segment.match?(PARAMETER)
          next segment if PathPrefix.safe_segment?(segment) && segment.match?(/[A-Za-z]/)

          "*"
        end.join("/")
      end
    end
  end
end
