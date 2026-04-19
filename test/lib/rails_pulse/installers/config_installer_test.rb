require "test_helper"

module RailsPulse
  module Installers
    class ConfigInstallerTest < ActiveSupport::TestCase
      def setup
        @output = StringIO.new
        @installer = ConfigInstaller.new(output: @output)
      end

      def teardown
        Mocha::Mockery.instance.teardown
      end

      # Structure Tests

      test "installer has output attribute" do
        assert_respond_to @installer, :output
      end

      test "class method install creates instance and calls install" do
        output = StringIO.new
        ConfigInstaller.any_instance.expects(:install).returns({ status: :copied, path: "/path" })

        ConfigInstaller.install(output: output)
      end

      # Install Method Tests

      test "install returns hash with status and path" do
        File.stubs(:exist?).returns(false)
        FileUtils.stubs(:cp)

        result = @installer.install

        assert_kind_of Hash, result
        assert_includes result.keys, :status
        assert_includes result.keys, :path
      end

      test "install skips when config already exists" do
        File.stubs(:exist?).returns(true)

        result = @installer.install

        assert_equal :skipped, result[:status]
        assert_includes @output.string, "Config already exists"
      end

      test "install copies config when it doesn't exist" do
        File.stubs(:exist?).returns(false)
        FileUtils.expects(:cp).once

        result = @installer.install

        assert_equal :copied, result[:status]
        assert_includes @output.string, "Copied example config"
      end

      test "install prints skip message with full path" do
        destination = Rails.root.join("config/initializers/rails_pulse.rb").to_s
        File.stubs(:exist?).returns(true)

        @installer.install

        assert_includes @output.string, destination
      end

      test "install prints copy message with full path" do
        destination = Rails.root.join("config/initializers/rails_pulse.rb").to_s
        File.stubs(:exist?).returns(false)
        FileUtils.stubs(:cp)

        @installer.install

        assert_includes @output.string, destination
      end

      # Path Tests

      test "source_file returns correct path" do
        source = @installer.send(:source_file)

        assert_kind_of String, source
        assert_includes source, "generators/rails_pulse/templates/rails_pulse.rb"
      end

      test "destination_file returns Rails root initializer path" do
        destination = @installer.send(:destination_file)

        expected = File.join(Rails.root, "config/initializers/rails_pulse.rb")

        assert_equal expected, destination
      end

      # Config Exists Tests

      test "config_exists? returns true when file exists" do
        File.stubs(:exist?).returns(true)

        assert @installer.send(:config_exists?)
      end

      test "config_exists? returns false when file doesn't exist" do
        File.stubs(:exist?).returns(false)

        refute @installer.send(:config_exists?)
      end

      test "config_exists? checks destination_file path" do
        File.expects(:exist?).with(@installer.send(:destination_file)).returns(false)

        @installer.send(:config_exists?)
      end

      # Copy Config Tests

      test "copy_config uses FileUtils.cp" do
        FileUtils.expects(:cp).with(
          @installer.send(:source_file),
          @installer.send(:destination_file)
        )

        @installer.send(:copy_config)
      end

      test "copy_config outputs success message" do
        FileUtils.stubs(:cp)

        @installer.send(:copy_config)

        assert_includes @output.string, "Copied example config"
      end

      # Skip Existing Config Tests

      test "skip_existing_config outputs skip message" do
        @installer.send(:skip_existing_config)

        assert_includes @output.string, "already exists"
      end

      test "skip_existing_config includes skipping keyword" do
        @installer.send(:skip_existing_config)

        assert_includes @output.string, "skipping"
      end

      # Integration Tests

      test "install can be called multiple times safely" do
        File.stubs(:exist?).returns(true)

        result1 = @installer.install
        result2 = @installer.install

        assert_equal :skipped, result1[:status]
        assert_equal :skipped, result2[:status]
      end

      test "install returns path regardless of status" do
        File.stubs(:exist?).returns(true)

        result = @installer.install

        assert_predicate result[:path], :present?
        assert_includes result[:path], "config/initializers/rails_pulse.rb"
      end
    end
  end
end
