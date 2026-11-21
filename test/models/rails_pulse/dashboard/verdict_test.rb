require "test_helper"

module RailsPulse
  module Dashboard
    class VerdictTest < ActiveSupport::TestCase
      HEALTHY = { healthy: 5, slow: 0, critical: 0 }.freeze
      NO_ATTENTION = { critical: [], warning: [], total: 0 }.freeze

      # Structure Tests

      test "an all-healthy app is operational with no action" do
        verdict = build_verdict

        assert_equal :ok, verdict.state
        assert_equal "Operational", verdict.status_label
        assert_equal "All systems operational", verdict.title
        assert_equal "Nothing is slow, failing or firing.", verdict.summary
        assert_nil verdict.action
      end

      test "areas appear in a fixed order with their page links" do
        verdict = build_verdict

        assert_equal %w[Routes Queries Jobs Exceptions], verdict.areas.map(&:name)
        assert_equal RailsPulse::Engine.routes.url_helpers.routes_path, verdict.areas.first.url
      end

      test "an area missing from the health summary has no cell" do
        verdict = build_verdict(jobs: nil, exceptions: nil)

        assert_equal %w[Routes Queries], verdict.areas.map(&:name)
      end

      test "tracking and storage cells appear only under pressure" do
        assert_not_includes build_verdict(tracking: HEALTHY, storage: HEALTHY).areas.map(&:name), "Tracking"

        names = build_verdict(tracking: { healthy: 1, slow: 0, critical: 1 }, storage: { healthy: 0, slow: 1, critical: 0 }).areas.map(&:name)

        assert_includes names, "Tracking"
        assert_includes names, "Storage"
      end

      test "only the exceptions cell carries a description" do
        verdict = build_verdict

        exceptions = verdict.areas.find { |area| area.name == "Exceptions" }

        assert_includes exceptions.description, "in the last 7 days"
        assert_includes exceptions.description, "Groups with 10+ occurrences are listed under Needs Attention"
        assert_nil verdict.areas.find { |area| area.name == "Routes" }.description
      end

      # Calculation Tests

      test "the worst area sets the overall state" do
        assert_equal :warning, build_verdict(routes: { healthy: 4, slow: 1, critical: 0 }).state
        assert_equal :critical, build_verdict(routes: { healthy: 4, slow: 1, critical: 0 }, queries: { healthy: 1, slow: 0, critical: 1 }).state
      end

      test "a Needs Attention entry alone raises the state" do
        attention = { critical: [ { name: "/slow" } ], warning: [], total: 1 }

        assert_equal :critical, build_verdict(needs_attention: attention).state
      end

      test "one or two problems are named in the headline" do
        verdict = build_verdict(exceptions: { healthy: 0, slow: 9, critical: 0 })

        assert_equal "9 exceptions firing", verdict.title
        assert_equal "Routes, queries, and jobs are healthy.", verdict.summary
        assert_equal "Degraded", verdict.status_label
      end

      test "a lone healthy area with a plural name takes a plural verb" do
        verdict = build_verdict(
          routes: { healthy: 3, slow: 1, critical: 0 },
          queries: { healthy: 3, slow: 1, critical: 0 },
          exceptions: { healthy: 0, slow: 2, critical: 0 }
        )

        assert_includes verdict.summary, "Jobs are healthy."
      end

      test "an area with nothing tracked is not called healthy" do
        verdict = build_verdict(
          routes: { healthy: 4, slow: 1, critical: 0 },
          jobs: { healthy: 0, slow: 0, critical: 0 }
        )

        assert_equal "Queries and exceptions are healthy.", verdict.summary
      end

      test "a single item is named in the singular" do
        verdict = build_verdict(routes: { healthy: 4, slow: 0, critical: 1 })

        assert_equal "1 route critical", verdict.title
      end

      test "more than two problems are counted by severity instead" do
        attention = { critical: [ {}, {} ], warning: [ {}, {}, {} ], total: 5 }
        verdict = build_verdict(
          routes: { healthy: 3, slow: 1, critical: 1 },
          queries: { healthy: 3, slow: 1, critical: 0 },
          needs_attention: attention
        )

        assert_equal "2 critical and 3 warnings", verdict.title
        assert_equal "Across routes and queries. Jobs and exceptions are healthy.", verdict.summary
      end

      test "an area with both critical and slow items shows the breakdown" do
        routes = build_verdict(routes: { healthy: 3, slow: 1, critical: 2 }).areas.first

        assert_equal 3, routes.count
        assert_equal "need attention", routes.label
        assert_equal "2 critical · 1 slow", routes.detail
      end

      test "an area uses its own labels for its counts" do
        jobs = build_verdict(jobs: { healthy: 9, slow: 0, critical: 1 }).areas.find { |area| area.name == "Jobs" }

        assert_equal 1, jobs.count
        assert_equal "failing", jobs.label
        assert_equal "9 healthy", jobs.detail
      end

      test "the meter keeps only non-zero segments" do
        routes = build_verdict(routes: { healthy: 3, slow: 0, critical: 1 }).areas.first

        assert_equal({ critical: 1, ok: 3 }, routes.meter)
      end

      test "the action reviews Needs Attention when it has entries" do
        attention = { critical: [ {} ], warning: [ {} ], total: 2 }

        action = build_verdict(needs_attention: attention).action

        assert_equal "Review 2 issues", action.label
        assert_equal "#needs-attention", action.url
      end

      test "the action opens the worst area when Needs Attention is empty" do
        action = build_verdict(
          routes: { healthy: 4, slow: 1, critical: 0 },
          exceptions: { healthy: 0, slow: 0, critical: 2 }
        ).action

        assert_equal "Open exceptions", action.label
        assert_equal RailsPulse::Engine.routes.url_helpers.exceptions_path, action.url
      end

      # Edge Cases

      test "an area with nothing tracked shows zero rather than healthy" do
        jobs = build_verdict(jobs: { healthy: 0, slow: 0, critical: 0 }).areas.find { |area| area.name == "Jobs" }

        assert_equal 0, jobs.count
        assert_equal "tracked", jobs.label
        assert_empty jobs.meter
        assert_equal :ok, jobs.state
      end

      test "an area where every item is critical has no healthy detail" do
        routes = build_verdict(routes: { healthy: 0, slow: 0, critical: 4 }).areas.first

        assert_equal "", routes.detail
      end

      test "every area troubled leaves no healthy sentence" do
        troubled = { healthy: 0, slow: 1, critical: 0 }
        verdict = build_verdict(routes: troubled, queries: troubled, jobs: nil, exceptions: nil)

        assert_equal "1 route slow and 1 query slow", verdict.title
        assert_equal "Every area needs a look.", verdict.summary
      end

      test "a raised state with no troubled area counts the attention items" do
        attention = { critical: [], warning: [ {} ], total: 1 }

        assert_equal "1 warning", build_verdict(needs_attention: attention).title
      end

      test "large counts are delimited in the headline" do
        verdict = build_verdict(queries: { healthy: 0, slow: 1_200, critical: 0 })

        assert_equal "1,200 queries slow", verdict.title
      end

      private

      def build_verdict(needs_attention: NO_ATTENTION, **health)
        summary = { routes: HEALTHY, queries: HEALTHY, jobs: HEALTHY, exceptions: HEALTHY, tracking: nil, storage: nil }.merge(health)
        Verdict.new(health_summary: summary, needs_attention: needs_attention, range_label: "last 7 days")
      end
    end
  end
end
