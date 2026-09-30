require "test_helper"
require "open3"

module RailsPulse
  # Everything under app/ is loaded by the host's Zeitwerk autoloader, which
  # derives constant names from file names through the host's inflections. A
  # host that declares `inflect.acronym "SQL"` must still get
  # RailsPulse::SqlQueryNormalizer from sql_query_normalizer.rb, or production
  # (eager_load = true) fails to boot.
  class ZeitwerkTest < ActiveSupport::TestCase
    DUMMY_ROOT = File.expand_path("../../dummy", __dir__)

    test "eager loading succeeds when the host declares acronym inflections" do
      # COVERAGE => nil: the child must not inherit the coverage cell's
      # SimpleCov, whose minimum-coverage at_exit gate exits 2 on a process
      # that only boots the app.
      env = {
        "RAILS_ENV" => "test",
        "RAILS_PULSE_TEST_ACRONYMS" => "SQL,CSP,API",
        "DB" => ENV.fetch("DB", "sqlite3"),
        "COVERAGE" => nil
      }
      output, status = Open3.capture2e(env, "bundle", "exec", "rails", "zeitwerk:check", chdir: DUMMY_ROOT)

      assert_predicate status, :success?, output
      assert_includes output, "All is good!"
    end

    test "acronym-safe inflections resolve to the constants the files define" do
      inflector = Rails.autoloaders.main.inflector

      engine_app = RailsPulse::Engine.root.join("app", "controllers", "rails_pulse").to_s

      RailsPulse::Engine::ACRONYM_SAFE_INFLECTIONS.each do |basename, constant|
        assert_equal constant, inflector.camelize(basename, File.join(engine_app, basename))
      end
    end

    test "acronym-safe inflections leave the host's files to the host's inflector" do
      fallback = Object.new
      def fallback.camelize(basename, _abspath) = "Host#{basename}"
      inflector = RailsPulse::ScopedInflector.new(fallback, root: "/gems/rails_pulse/app", overrides: { "api" => "Api" })

      assert_equal "Api", inflector.camelize("api", "/gems/rails_pulse/app/controllers/rails_pulse/api")
      assert_equal "Hostapi", inflector.camelize("api", "/srv/host/app/controllers/api")
      assert_equal "Hostapi", inflector.camelize("api", "/gems/rails_pulse/application/api")
    end

    test "host inflections registered after boot reach the host's inflector" do
      received = nil
      fallback = Object.new
      fallback.define_singleton_method(:inflect) { |overrides| received = overrides }
      inflector = RailsPulse::ScopedInflector.new(fallback, root: "/gems/rails_pulse/app", overrides: {})

      inflector.inflect("html_parser" => "HTMLParser")

      assert_equal({ "html_parser" => "HTMLParser" }, received)
    end
  end
end
