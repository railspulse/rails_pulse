require "test_helper"

class RailsPulse::PackagedAssetsTest < ActiveSupport::TestCase
  def setup
    super
    @destination = Pathname.new(Dir.mktmpdir)
    RailsPulse::PackagedAssets.reset!
  end

  def teardown
    FileUtils.remove_entry(@destination) if @destination&.exist?
    RailsPulse::PackagedAssets.reset!
    super
  end

  test "install_assets rake task is registered" do
    Rails.application.load_tasks

    assert Rake::Task.task_defined?("rails_pulse:install_assets")
  end

  test "install copies digested files and writes a manifest" do
    entries = RailsPulse::PackagedAssets.install!(destination: @destination)

    assert_includes entries.keys, "rails-pulse.css"
    assert_includes entries.keys, "rails-pulse.js"
    assert_match(/\Arails-pulse-[a-f0-9]{64}\.css\z/, entries["rails-pulse.css"])
    assert_predicate @destination.join(entries["rails-pulse.css"]), :exist?
    assert_predicate @destination.join(entries["rails-pulse.js"]), :exist?
    assert_equal entries, JSON.parse(@destination.join(".rails-pulse-manifest.json").read)
  end

  test "install does not modify the source files" do
    source = RailsPulse::Engine.root.join("public/rails-pulse-assets/rails-pulse.css")
    before = Digest::SHA256.file(source).hexdigest

    RailsPulse::PackagedAssets.install!(destination: @destination)

    assert_equal before, Digest::SHA256.file(source).hexdigest
  end

  test "install copies source maps next to the JS and CSS" do
    RailsPulse::PackagedAssets.install!(destination: @destination)

    assert_predicate @destination.join("rails-pulse.js.map"), :exist?
    assert_predicate @destination.join("rails-pulse.css.map"), :exist?
  end

  test "install patches an existing Propshaft manifest" do
    File.write(@destination.join(".manifest.json"), { "application.css" => "application-aaa.css" }.to_json)

    entries = RailsPulse::PackagedAssets.install!(destination: @destination)
    merged = JSON.parse(@destination.join(".manifest.json").read)

    assert_equal "application-aaa.css", merged["application.css"]
    assert_equal entries["rails-pulse.css"], merged["rails-pulse.css"]
  end

  test "install patches an existing Sprockets manifest" do
    sprockets = @destination.join(".sprockets-manifest-test.json")
    File.write(sprockets, { "assets" => { "application.js" => "application-aaa.js" }, "files" => {} }.to_json)

    entries = RailsPulse::PackagedAssets.install!(destination: @destination)
    data = JSON.parse(sprockets.read)

    assert_equal "application-aaa.js", data["assets"]["application.js"]
    assert_equal entries["rails-pulse.js"], data["assets"]["rails-pulse.js"]
    assert_equal "rails-pulse.js", data["files"][entries["rails-pulse.js"]]["logical_path"]
  end

  test "url_path is nil when no manifest is present" do
    empty = Pathname.new(Dir.mktmpdir)
    Rails.stubs(:public_path).returns(empty)
    RailsPulse::PackagedAssets.reset!

    assert_nil RailsPulse::PackagedAssets.url_path("rails-pulse.css")
  ensure
    Rails.unstub(:public_path)
    FileUtils.remove_entry(empty) if empty&.exist?
    RailsPulse::PackagedAssets.reset!
  end

  test "url_path returns a public assets path from the manifest" do
    public_dir = Pathname.new(Dir.mktmpdir)
    assets_dir = public_dir.join("assets")
    RailsPulse::PackagedAssets.install!(destination: assets_dir)

    Rails.stubs(:public_path).returns(public_dir)
    RailsPulse::PackagedAssets.reset!

    assert_match %r{\A/assets/rails-pulse-[a-f0-9]{64}\.css\z}, RailsPulse::PackagedAssets.url_path("rails-pulse.css")
  ensure
    Rails.unstub(:public_path)
    FileUtils.remove_entry(public_dir) if public_dir&.exist?
  end

  test "uninstall removes copied files and the manifest" do
    entries = RailsPulse::PackagedAssets.install!(destination: @destination)
    RailsPulse::PackagedAssets.uninstall!(destination: @destination)

    refute_predicate @destination.join(".rails-pulse-manifest.json"), :exist?
    refute_predicate @destination.join(entries["rails-pulse.css"]), :exist?
  end
end
