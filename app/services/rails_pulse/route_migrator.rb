module RailsPulse
  class RouteMigrator
    def self.call
      new.call
    end

    def call
      sync_id_sequence!
      results = { merged: 0, skipped: 0, unchanged: 0 }
      RailsPulse::Route.find_each { |route| process_route(route, results) }
      results
    end

    private

    def process_route(route, results)
      # Skip rows already destroyed by an earlier merge in this run.
      return unless RailsPulse::Route.exists?(id: route.id)

      primary_method = route.http_methods_list.first
      return results[:skipped] += 1 unless primary_method

      params = RailsPulse::RouteRecognizer.call(route.path, method: primary_method)
      return results[:skipped] += 1 unless params

      normalized = RailsPulse::RoutePathNormalizer.normalize(route.path, params)

      # Derive controller_action from the recognized route params if not already stored.
      recognized_ca = [ params[:controller], params[:action] ].compact.join("#").presence

      if normalized == route.path
        assign_or_merge_controller_action(route, recognized_ca, results)
        return
      end

      ca_for_target = recognized_ca || route.controller_action
      target = find_or_create_normalized_route(route, ca_for_target, normalized)
      RailsPulse::RouteMerger.call(target: target, source: route) unless target.id == route.id

      results[:merged] += 1
    end

    def assign_or_merge_controller_action(route, recognized_ca, results)
      if route.controller_action.nil? && recognized_ca.present?
        existing = RailsPulse::Route.find_by(controller_action: recognized_ca, path: route.path)
        if existing && existing.id != route.id
          RailsPulse::RouteMerger.call(target: existing, source: route)
          results[:merged] += 1
          return
        end

        begin
          route.update_column(:controller_action, recognized_ca)
        rescue ActiveRecord::RecordNotUnique
          existing = RailsPulse::Route.find_by(controller_action: recognized_ca, path: route.path)
          if existing && existing.id != route.id
            RailsPulse::RouteMerger.call(target: existing, source: route)
            results[:merged] += 1
            return
          end
          raise
        end
      end

      results[:unchanged] += 1
    end

    # Find an existing normalized route, or create one. Handles two RecordNotUnique cases:
    # 1. Concurrent create on [controller_action, path] — find and return the winner
    # 2. Stale PK sequence (id already taken) — resync sequence and retry create
    def find_or_create_normalized_route(route, controller_action, path)
      existing = RailsPulse::Route.find_by(controller_action: controller_action, path: path)
      return existing if existing

      attrs = {
        http_methods: route.http_methods,
        path: path,
        controller_action: controller_action,
        tags: route.tags || "[]"
      }

      RailsPulse::Route.create!(attrs)
    rescue ActiveRecord::RecordNotUnique => e
      existing = RailsPulse::Route.find_by(controller_action: controller_action, path: path)
      return existing if existing

      raise unless primary_key_conflict?(e)

      sync_id_sequence!
      RailsPulse::Route.create!(attrs)
    end

    def primary_key_conflict?(error)
      message = error.message.to_s
      message.include?("rails_pulse_routes_pkey") ||
        message.include?("PRIMARY KEY") ||
        message.match?(/unique constraint.*\bids?\b/i)
    end

    def sync_id_sequence!
      connection = RailsPulse::Route.connection
      table = RailsPulse::Route.table_name
      max_id = RailsPulse::Route.maximum(:id).to_i
      return if max_id.zero?

      case connection.adapter_name.downcase
      when /postgres/
        sequence = connection.select_value(
          "SELECT pg_get_serial_sequence(#{connection.quote(table)}, 'id')"
        )
        return unless sequence

        connection.execute(
          "SELECT setval(#{connection.quote(sequence)}, #{max_id}, true)"
        )
      when /mysql/
        connection.execute(
          "ALTER TABLE #{connection.quote_table_name(table)} AUTO_INCREMENT = #{max_id + 1}"
        )
      when /sqlite/
        quoted_table = connection.quote(table)
        exists = connection.select_value(
          "SELECT 1 FROM sqlite_sequence WHERE name = #{quoted_table}"
        )
        if exists
          connection.execute(
            "UPDATE sqlite_sequence SET seq = #{max_id} WHERE name = #{quoted_table}"
          )
        end
      end
    rescue ActiveRecord::StatementInvalid
      # Best-effort; create will raise a clearer error if the sequence is still wrong.
    end
  end
end
