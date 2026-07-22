require "test_helper"

module RailsPulse
  class RouteMigratorTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_requests

    # Migration Tests

    test "normalizes raw path route and reassigns requests" do
      raw_route = create_route("GET", "/posts/42")
      request   = create_request(raw_route)

      RailsPulse::RouteMigrator.call

      assert_nil RailsPulse::Route.find_by(path: "/posts/42"),
        "raw route should be destroyed after merge"

      normalized = RailsPulse::Route.find_by(path: "/posts/:id")
      assert normalized, "normalized route should exist"
      assert_equal normalized.id, request.reload.route_id,
        "request should be reassigned to normalized route"
    end

    test "merges multiple raw paths for same pattern into one normalized route" do
      raw1 = create_route("GET", "/posts/42")
      raw2 = create_route("GET", "/posts/99")
      req1 = create_request(raw1)
      req2 = create_request(raw2)

      RailsPulse::RouteMigrator.call

      normalized = RailsPulse::Route.find_by(path: "/posts/:id")
      assert normalized
      assert_equal normalized.id, req1.reload.route_id
      assert_equal normalized.id, req2.reload.route_id
      assert_equal 1, RailsPulse::Route.where(path: "/posts/:id").count
    end

    test "normalizes nested parameterized path with correct param names" do
      raw_route = create_route("GET", "/partners/acme-corp/submissions/SLKe-2342-234")

      RailsPulse::RouteMigrator.call

      assert_nil RailsPulse::Route.find_by(path: "/partners/acme-corp/submissions/SLKe-2342-234")
      assert RailsPulse::Route.find_by(path: "/partners/:client_id/submissions/:uuid")
    end

    # Unchanged / Skipped Tests

    test "leaves unrecognized paths unchanged" do
      raw_route = create_route("GET", "/nonexistent/route/123")

      RailsPulse::RouteMigrator.call

      assert RailsPulse::Route.exists?(id: raw_route.id)
    end

    test "leaves already-normalized paths unchanged" do
      normalized_route = create_route("GET", "/posts/:id")

      RailsPulse::RouteMigrator.call

      assert RailsPulse::Route.exists?(id: normalized_route.id)
    end

    test "merges unchanged-path route into existing controller_action collision" do
      existing = create_route("GET", "/posts/:id", controller_action: "home#index")
      duplicate = create_route("GET", "/posts/:id")
      request = create_request(duplicate)

      results = RailsPulse::RouteMigrator.call

      assert_not RailsPulse::Route.exists?(id: duplicate.id)
      assert_equal existing.id, request.reload.route_id
      assert_operator results[:merged], :>=, 1
    end

    test "recovers when normalized route create hits a stale primary key sequence" do
      raw_route = create_route("GET", "/posts/42")
      request = create_request(raw_route)

      original_create = RailsPulse::Route.method(:create!)
      calls = 0
      RailsPulse::Route.define_singleton_method(:create!) do |*args, **kwargs|
        attrs = args.first.is_a?(Hash) ? args.first : kwargs
        if attrs[:path] == "/posts/:id"
          calls += 1
          if calls == 1
            raise ActiveRecord::RecordNotUnique,
              'PG::UniqueViolation: duplicate key value violates unique constraint "rails_pulse_routes_pkey"'
          end
        end
        original_create.call(*args, **kwargs)
      end

      begin
        RailsPulse::RouteMigrator.call
      ensure
        RailsPulse::Route.define_singleton_method(:create!, original_create)
      end

      normalized = RailsPulse::Route.find_by(path: "/posts/:id")
      assert normalized
      assert_equal normalized.id, request.reload.route_id
      assert_equal 2, calls
    end

    test "merges into existing normalized route when create hits unique path constraint" do
      existing = create_route("GET", "/posts/:id", controller_action: "home#index")
      raw_route = create_route("GET", "/posts/42")
      request = create_request(raw_route)

      # Force the create path even though existing already matches — simulate a race
      # where find_by missed and create hit the unique index.
      original_find = RailsPulse::Route.method(:find_by)
      find_calls = 0
      RailsPulse::Route.define_singleton_method(:find_by) do |*args, **kwargs|
        attrs = args.first.is_a?(Hash) ? args.first : kwargs
        if attrs[:path] == "/posts/:id"
          find_calls += 1
          return nil if find_calls == 1
        end
        original_find.call(*args, **kwargs)
      end

      original_create = RailsPulse::Route.method(:create!)
      RailsPulse::Route.define_singleton_method(:create!) do |*args, **kwargs|
        attrs = args.first.is_a?(Hash) ? args.first : kwargs
        if attrs[:path] == "/posts/:id"
          raise ActiveRecord::RecordNotUnique,
            'PG::UniqueViolation: duplicate key value violates unique constraint "index_rails_pulse_routes_on_controller_action_and_path"'
        end
        original_create.call(*args, **kwargs)
      end

      begin
        RailsPulse::RouteMigrator.call
      ensure
        RailsPulse::Route.define_singleton_method(:find_by, original_find)
        RailsPulse::Route.define_singleton_method(:create!, original_create)
      end

      assert RailsPulse::Route.exists?(id: existing.id)
      assert_not RailsPulse::Route.exists?(id: raw_route.id)
      assert_equal existing.id, request.reload.route_id
    end

    # Results Hash Tests

    test "results hash reports at least one merged route" do
      create_route("GET", "/posts/42")

      results = RailsPulse::RouteMigrator.call

      assert_operator results[:merged], :>=, 1
    end

    test "results hash reports skipped for unrecognized paths" do
      create_route("GET", "/ghost/route/999")

      results = RailsPulse::RouteMigrator.call

      assert_operator results[:skipped], :>=, 1
    end

    test "results hash contains expected keys" do
      results = RailsPulse::RouteMigrator.call

      assert_kind_of Integer, results[:unchanged]
      assert_kind_of Integer, results[:merged]
      assert_kind_of Integer, results[:skipped]
    end

    # Transaction Safety Tests

    test "all requests reassigned before old route is destroyed" do
      raw_route = create_route("GET", "/posts/42")
      3.times { create_request(raw_route) }

      RailsPulse::RouteMigrator.call

      normalized = RailsPulse::Route.find_by(path: "/posts/:id")
      assert_equal 3, normalized.requests.count
    end

    private

    def create_route(http_method, path, controller_action: nil)
      RailsPulse::Route.create!(
        http_methods: [ http_method ].to_json,
        path: path,
        controller_action: controller_action,
        tags: "[]"
      )
    end

    def create_request(route)
      RailsPulse::Request.create!(
        route: route,
        method: route.http_methods_list.first,
        duration: 100.0,
        status: 200,
        is_error: false,
        request_uuid: SecureRandom.uuid,
        controller_action: "PostsController#show",
        occurred_at: Time.current
      )
    end
  end
end
