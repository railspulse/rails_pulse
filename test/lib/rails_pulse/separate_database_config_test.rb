require "test_helper"

module RailsPulse
  class SeparateDatabaseConfigTest < ActiveSupport::TestCase
    # Schema dump Tests

    test "schema_dump false yields no dump path so Rails will not load structure.sql" do
      cfg = ActiveRecord::DatabaseConfigurations::HashConfig.new(
        "production",
        "rails_pulse",
        {
          "adapter" => "postgresql",
          "database" => "rails_pulse_staging",
          "migrations_paths" => "db/rails_pulse_migrate",
          "schema_dump" => false
        }
      )

      assert_nil cfg.schema_dump
      assert_predicate cfg, :database_tasks?
      assert_nil ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(cfg)
    end

    test "schema_dump omitted dumps rails_pulse_structure.sql for sql format" do
      cfg = ActiveRecord::DatabaseConfigurations::HashConfig.new(
        "production",
        "rails_pulse",
        {
          "adapter" => "postgresql",
          "database" => "rails_pulse_staging",
          "migrations_paths" => "db/rails_pulse_migrate"
        }
      )

      # Pass :sql explicitly: Rails 7.2 ignores per-database schema_format.
      assert_equal "rails_pulse_structure.sql", cfg.schema_dump(:sql)
      assert_equal "rails_pulse_schema.rb", cfg.schema_dump(:ruby)
    end

    test "dummy database.yml sets schema_dump false on rails_pulse" do
      yaml = File.read(Rails.root.join("config/database.yml"))

      assert_match(/schema_dump: false/, yaml)
    end
  end
end
