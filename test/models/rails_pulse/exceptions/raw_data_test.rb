require "test_helper"

module RailsPulse
  module Exceptions
    class RawDataTest < ActiveSupport::TestCase
      fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

      def setup
        ENV["TEST_TYPE"] = "functional"
        super
        @group = rails_pulse_exception_groups(:record_not_found)
        @occurrence = rails_pulse_exception_occurrences(:occurrence_one)
      end

      def report(group = @group, **options)
        RawData.new(group, **options).to_s
      end

      # Structure Tests

      test "renders the exception class as the heading" do
        assert_includes report, "# Exception: ActiveRecord::RecordNotFound"
      end

      test "includes summary fields" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Summary"
        assert_includes output, "- Class: ActiveRecord::RecordNotFound"
        assert_includes output, "- Location: app/models/post.rb#find"
        assert_includes output, "- Status: open"
        assert_includes output, "- Fingerprint: #{@group.fingerprint}"
      end

      test "includes frequency counts" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Frequency"
        assert_includes output, "- Total occurrences (lifetime): 5"
        assert_includes output, "- Stored occurrences: 2"
        assert_includes output, "- Last 24 hours: 2"
      end

      test "distinguishes stored occurrences from the lifetime count" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "older rows may have been pruned by retention"
      end

      # Calculation Tests

      test "lists distinct deploy shas" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Deploys"
        assert_includes output, "abc1234"
      end

      test "omits the deploys section when no occurrence has a sha" do
        output = report(rails_pulse_exception_groups(:zero_division))

        refute_includes output, "## Deploys"
      end

      test "lists distinct endpoints in group mode" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Request context"
        assert_includes output, "- Endpoints:"
        assert_includes output, "GET /posts/999"
        assert_includes output, "GET /posts/998"
      end

      test "reports a single endpoint in occurrence mode" do
        output = report(@group, occurrence: @occurrence, aggregates: false)

        assert_includes output, "- Endpoint: GET /posts/999"
        refute_includes output, "GET /posts/998"
      end

      test "omits aggregate sections when aggregates are disabled" do
        output = report(@group, occurrence: @occurrence, aggregates: false)

        refute_includes output, "- Stored occurrences:"
        refute_includes output, "## Deploys"
      end

      # Backtrace Tests

      test "lists backtrace frames" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Backtrace"
        assert_includes output, "posts_controller.rb:42:in `show'"
        assert_includes output, "post.rb:10:in `find'"
      end

      # Real captures store absolute paths, which is what the app/gem split keys off.
      test "tags frames as app or gem" do
        @occurrence.update!(backtrace: [
          { "file" => "/srv/myapp/app/controllers/posts_controller.rb", "line" => 42, "method" => "show" },
          { "file" => "/srv/bundle/gems/activerecord-8.0.0/lib/active_record/core.rb", "line" => 12, "method" => "find" }
        ])

        output = report(@group, occurrence: @occurrence)

        assert_includes output, "[app] /app/controllers/posts_controller.rb:42:in `show'"
        assert_includes output, "[gem] activerecord-8.0.0/lib/active_record/core.rb:12:in `find'"
      end

      test "numbers backtrace frames in order" do
        output = report(@group, occurrence: @occurrence)

        assert_match(/ 1\. \[\w+\] .*posts_controller\.rb:42/, output)
        assert_match(/ 2\. \[\w+\] .*post\.rb:10/, output)
      end

      test "renders filtered request params as json" do
        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Request params (filtered)"
        assert_includes output, '"controller": "posts"'
      end

      # Source expansion is read from disk and sandboxed to Rails.root.
      test "inlines source lines for app frames that resolve on disk" do
        file = Rails.root.join("config/routes.rb").to_s
        @occurrence.update!(backtrace: [ { "file" => file, "line" => 2, "method" => "draw" } ])

        output = report(@group, occurrence: @occurrence)

        assert_includes output, "## Source"
        assert_includes output, "```ruby"
        assert_match(/>\s+2 \|/, output)
      end

      test "omits the source section when no frame resolves on disk" do
        @occurrence.update!(backtrace: [
          { "file" => "/srv/myapp/app/models/ghost.rb", "line" => 3, "method" => "call" }
        ])

        refute_includes report(@group, occurrence: @occurrence), "## Source"
      end

      # Edge Cases

      test "handles a group with no occurrence" do
        output = report(rails_pulse_exception_groups(:resolved_group))

        assert_includes output, "# Exception: ArgumentError"
        refute_includes output, "## Backtrace"
      end

      test "handles an occurrence with no request params" do
        output = report(@group, occurrence: rails_pulse_exception_occurrences(:occurrence_two))

        refute_includes output, "## Request params (filtered)"
      end

      test "handles an occurrence with no request url" do
        occurrence = rails_pulse_exception_occurrences(:occurrence_zero_division)
        output = report(rails_pulse_exception_groups(:zero_division), occurrence: occurrence, aggregates: false)

        refute_includes output, "- Endpoint:"
        assert_includes output, "- Environment: production"
      end

      test "falls back to the group message when the occurrence has none" do
        @occurrence.update!(message: nil)

        assert_includes report(@group, occurrence: @occurrence), "- Message: #{@group.message}"
      end

      test "ends with a single trailing newline" do
        assert_equal "\n", report[-1]
        refute_equal "\n", report[-2]
      end
    end
  end
end
