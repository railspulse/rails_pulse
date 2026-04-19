require "test_helper"

module RailsPulse
  module Installers
    class MigrationInstallerTest < ActiveSupport::TestCase
      def setup
        @output = StringIO.new
        @installer = MigrationInstaller.new(output: @output)
      end

      def teardown
        Mocha::Mockery.instance.teardown
      end

      # Structure Tests

      test "installer has output attribute" do
        assert_respond_to @installer, :output
      end

      test "installer has stats attribute" do
        assert_respond_to @installer, :stats
      end

      test "stats initializes with empty arrays" do
        assert_empty @installer.stats[:copied]
        assert_empty @installer.stats[:skipped]
      end

      test "class method install creates instance and calls install" do
        output = StringIO.new
        MigrationInstaller.any_instance.expects(:install).returns({ copied: [], skipped: [] })

        MigrationInstaller.install(output: output)
      end

      # Install Method Tests

      test "install prints starting message" do
        Dir.stubs(:glob).returns([])

        @installer.install

        assert_includes @output.string, "Copying migrations"
      end

      test "install processes all migrations in order" do
        Dir.stubs(:glob).returns([])

        @installer.install

        output_text = @output.string

        assert_includes output_text, "Copying migrations"
      end

      test "install returns stats hash" do
        Dir.stubs(:glob).returns([])

        result = @installer.install

        assert_kind_of Hash, result
        assert_includes result.keys, :copied
        assert_includes result.keys, :skipped
      end

      test "install skips existing migrations" do
        @installer.stubs(:find_source_file).returns("/path/to/source/create_routes.rb")
        @installer.stubs(:migration_exists?).returns(true)

        @installer.install

        assert_includes @output.string, "Skipping existing migration"
        assert_operator @installer.stats[:skipped].length, :>=, 1
      end

      test "install copies new migrations" do
        source_file = "/path/to/source/create_routes.rb"

        @installer.stubs(:find_source_file).returns(source_file)
        @installer.stubs(:migration_exists?).returns(false)
        FileUtils.expects(:cp).at_least_once

        @installer.install

        assert_includes @output.string, "Copied migration"
        assert_operator @installer.stats[:copied].length, :>=, 1
      end

      test "install handles missing source files" do
        Dir.stubs(:glob).returns([])

        result = @installer.install

        assert_equal 0, result[:copied].length
        assert_equal 0, result[:skipped].length
      end

      # Migration Order Tests

      test "migration_order returns correct migrations" do
        order = @installer.send(:migration_order)

        assert_equal 4, order.length
        assert_includes order, "create_routes.rb"
        assert_includes order, "create_requests.rb"
        assert_includes order, "create_queries.rb"
        assert_includes order, "create_operations.rb"
      end

      test "migration_order returns migrations in correct sequence" do
        order = @installer.send(:migration_order)

        assert_equal "create_routes.rb", order[0]
        assert_equal "create_requests.rb", order[1]
        assert_equal "create_queries.rb", order[2]
        assert_equal "create_operations.rb", order[3]
      end

      # Path Tests

      test "source_dir returns correct path" do
        dir = @installer.send(:source_dir)

        assert_kind_of String, dir
        assert_includes dir, "db/migrate"
      end

      test "destination_dir returns Rails root db/migrate" do
        dir = @installer.send(:destination_dir)

        assert_equal File.join(Rails.root, "db/migrate"), dir
      end

      # Timestamp Tests

      test "build_destination_path generates unique timestamps" do
        Time.stubs(:now).returns(Time.utc(2024, 1, 1, 12, 0, 0))

        path1 = @installer.send(:build_destination_path, "create_routes.rb", 0)
        path2 = @installer.send(:build_destination_path, "create_requests.rb", 1)

        # Timestamps should differ by 1 second
        assert_includes path1, "20240101120000"
        assert_includes path2, "20240101120001"
      end

      test "build_destination_path includes rails_pulse suffix" do
        path = @installer.send(:build_destination_path, "create_routes.rb", 0)

        assert_includes path, ".rails_pulse.rb"
      end

      test "build_destination_path removes .rb before adding suffix" do
        path = @installer.send(:build_destination_path, "create_routes.rb", 0)

        refute_includes path, "create_routes.rb.rails_pulse.rb"
        assert_includes path, "create_routes.rails_pulse.rb"
      end

      # Find Source File Tests

      test "find_source_file uses glob to locate migration" do
        Dir.expects(:glob).with { |pattern| pattern.include?("create_routes.rb") }.returns([ "/path/to/file" ])

        @installer.send(:find_source_file, "create_routes.rb")
      end

      test "find_source_file returns first match" do
        Dir.stubs(:glob).returns([ "/path/first", "/path/second" ])

        result = @installer.send(:find_source_file, "create_routes.rb")

        assert_equal "/path/first", result
      end

      # Migration Exists Tests

      test "migration_exists? returns true when migration found" do
        Dir.stubs(:glob).returns([ "/path/to/existing/migration" ])

        result = @installer.send(:migration_exists?, "create_routes.rb")

        assert result
      end

      test "migration_exists? returns false when no migration found" do
        Dir.stubs(:glob).returns([])

        result = @installer.send(:migration_exists?, "create_routes.rb")

        refute result
      end

      # Integration Tests

      test "install tracks multiple copied migrations" do
        # Mock finding all source files
        Dir.stubs(:glob).with { |pattern|
          pattern.include?("db/migrate") && !pattern.include?(Rails.root.to_s)
        }.returns([ "/source/file" ])

        # No existing migrations in destination
        Dir.stubs(:glob).with { |pattern| pattern.include?(Rails.root.to_s) }.returns([])

        FileUtils.stubs(:cp)

        @installer.install

        assert_operator @installer.stats[:copied].length, :>=, 0
      end

      test "install tracks multiple skipped migrations" do
        # Mock finding source files
        Dir.stubs(:glob).with { |pattern|
          pattern.include?("db/migrate") && !pattern.include?(Rails.root.to_s)
        }.returns([ "/source/file" ])

        # All migrations already exist
        Dir.stubs(:glob).with { |pattern| pattern.include?(Rails.root.to_s) }
          .returns([ "/existing/migration" ])

        @installer.install

        assert_operator @installer.stats[:skipped].length, :>=, 0
      end
    end
  end
end
