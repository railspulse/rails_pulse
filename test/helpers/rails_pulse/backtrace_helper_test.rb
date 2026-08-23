require "test_helper"
require "tempfile"

class RailsPulse::BacktraceHelperTest < ActionView::TestCase
  include RailsPulse::BacktraceHelper

  # ============================================================================
  # app_frame?
  # ============================================================================

  test "app_frame? returns true for /app/ path" do
    assert app_frame?("file" => "/home/user/myapp/app/controllers/posts_controller.rb")
  end

  test "app_frame? returns true for /lib/ path" do
    assert app_frame?("file" => "/home/user/myapp/lib/my_service.rb")
  end

  test "app_frame? returns true for /config/ path" do
    assert app_frame?("file" => "/home/user/myapp/config/initializers/devise.rb")
  end

  test "app_frame? returns false for gem path" do
    refute app_frame?("file" => "/usr/local/bundle/gems/activerecord-7.0.0/lib/active_record.rb")
  end

  test "app_frame? returns false for rubygems path" do
    refute app_frame?("file" => "/usr/local/lib/ruby/gems/3.2.0/gems/rack-3.0.0/lib/rack.rb")
  end

    test "app_frame? returns false for stdlib path" do
    refute app_frame?("file" => "/usr/local/lib/ruby/3.2.0/json.rb")
  end

  test "app_frame? returns true for a project path that contains ruby" do
    assert app_frame?("file" => "/Users/dev/ruby_app/app/models/user.rb")
  end

  test "app_frame? returns false for blank file" do
    refute app_frame?("file" => "")
  end

  test "app_frame? returns false for nil file" do
    refute app_frame?("file" => nil)
  end

  test "app_frame? returns false when /app/ appears inside a gem path" do
    refute app_frame?("file" => "/usr/local/bundle/gems/my_app_gem-1.0/app/models/foo.rb")
  end

  # ============================================================================
  # frame_display_path
  # ============================================================================

  test "frame_display_path strips versioned gems prefix" do
    frame = { "file" => "/usr/local/bundle/ruby/3.2.0/gems/activerecord-7.0.4/lib/active_record/base.rb" }

    assert_equal "activerecord-7.0.4/lib/active_record/base.rb", frame_display_path(frame)
  end

  test "frame_display_path strips bundler path gem prefix" do
    frame = { "file" => "/home/user/src/gems/my_gem/lib/my_gem.rb" }

    assert_equal "my_gem/lib/my_gem.rb", frame_display_path(frame)
  end

  test "frame_display_path returns /app/... for app controller frames" do
    frame = { "file" => "/home/deploy/myapp/app/controllers/posts_controller.rb" }

    assert_equal "/app/controllers/posts_controller.rb", frame_display_path(frame)
  end

  test "frame_display_path returns /lib/... for lib frames" do
    frame = { "file" => "/home/deploy/myapp/lib/my_service.rb" }

    assert_equal "/lib/my_service.rb", frame_display_path(frame)
  end

  test "frame_display_path returns /config/... for config frames" do
    frame = { "file" => "/home/deploy/myapp/config/initializers/sentry.rb" }

    assert_equal "/config/initializers/sentry.rb", frame_display_path(frame)
  end

  test "frame_display_path falls back to basename for unrecognised paths" do
    frame = { "file" => "/home/user/tmp/cache/file.rb" }

    assert_equal "file.rb", frame_display_path(frame)
  end

  test "frame_display_path handles blank file" do
    frame = { "file" => "" }

    assert_equal "", frame_display_path(frame)
  end

  test "frame_display_path handles nil file" do
    frame = { "file" => nil }

    assert_equal "", frame_display_path(frame)
  end

  # ============================================================================
  # frame_dirname
  # ============================================================================

  test "frame_dirname returns directory with trailing slash for app frame" do
    frame = { "file" => "/home/deploy/myapp/app/controllers/posts_controller.rb" }

    assert_equal "/app/controllers/", frame_dirname(frame)
  end

  test "frame_dirname returns directory with trailing slash for gem frame" do
    frame = { "file" => "/bundle/ruby/3.2.0/gems/rack-3.0.0/lib/rack/request.rb" }

    assert_equal "rack-3.0.0/lib/rack/", frame_dirname(frame)
  end

  test "frame_dirname returns ./ for a bare filename fallback" do
    frame = { "file" => "/home/user/tmp/cache/json.rb" }

    assert_equal "./", frame_dirname(frame)
  end

  # ============================================================================
  # frame_basename
  # ============================================================================

  test "frame_basename returns filename for app frame" do
    frame = { "file" => "/home/deploy/myapp/app/controllers/posts_controller.rb" }

    assert_equal "posts_controller.rb", frame_basename(frame)
  end

  test "frame_basename returns filename for gem frame" do
    frame = { "file" => "/bundle/ruby/3.2.0/gems/rack-3.0.0/lib/rack/request.rb" }

    assert_equal "request.rb", frame_basename(frame)
  end

  test "frame_basename returns filename for fallback path" do
    frame = { "file" => "/usr/local/lib/ruby/3.2.0/json.rb" }

    assert_equal "json.rb", frame_basename(frame)
  end

  # ============================================================================
  # frame_source_lines
  # ============================================================================

  test "frame_source_lines returns lines centred on the target line" do
    with_source_file((1..20).map { |i| "line #{i}" }.join("\n")) do |path|
      result = frame_source_lines({ "file" => path, "line" => 10 })

      assert_equal (7..13).to_a, result.keys
      assert_equal "line 10", result[10]
    end
  end

  test "frame_source_lines clamps to line 1 at the top of the file" do
    with_source_file((1..10).map { |i| "line #{i}" }.join("\n")) do |path|
      result = frame_source_lines({ "file" => path, "line" => 2 })

      assert_includes result.keys, 1
      assert_equal "line 1", result[1]
    end
  end

  test "frame_source_lines respects a custom radius" do
    with_source_file((1..20).map { |i| "line #{i}" }.join("\n")) do |path|
      result = frame_source_lines({ "file" => path, "line" => 10 }, radius: 1)

      assert_equal [ 9, 10, 11 ], result.keys
    end
  end

  test "frame_source_lines returns nil for missing file" do
    frame = { "file" => "/nonexistent/path/file.rb", "line" => 5 }

    assert_nil frame_source_lines(frame)
  end

  test "frame_source_lines returns nil for blank file" do
    assert_nil frame_source_lines({ "file" => "", "line" => 1 })
  end

  test "frame_source_lines returns nil for nil file" do
    assert_nil frame_source_lines({ "file" => nil, "line" => 1 })
  end

  test "frame_source_lines returns nil when line is zero" do
    with_source_file("some content") do |path|
      assert_nil frame_source_lines({ "file" => path, "line" => 0 })
    end
  end

  test "frame_source_lines returns nil when line is negative" do
    with_source_file("some content") do |path|
      assert_nil frame_source_lines({ "file" => path, "line" => -1 })
    end
  end

  test "frame_source_lines strips trailing whitespace from lines" do
    with_source_file("  indented line   \n") do |path|
      result = frame_source_lines({ "file" => path, "line" => 1 })

      assert_equal "  indented line", result[1]
    end
  end

  test "frame_source_lines returns empty hash when target line is beyond end of file" do
    with_source_file("only one line") do |path|
      # radius 3 makes first_line = max(5-3, 1) = 2, but file only has line 1
      result = frame_source_lines({ "file" => path, "line" => 5 })

      assert_empty result
    end
  end

  test "frame_source_lines returns nil for files outside Rails.root" do
    Tempfile.create([ "outside_rails_root", ".rb" ]) do |f|
      f.write("secret\n")
      f.flush

      assert_nil frame_source_lines({ "file" => f.path, "line" => 1 }),
        "must not read files outside Rails.root"
    end
  end

  # ============================================================================
  # APP_FRAME_PATTERN — consistency with ExceptionCaptureService
  # ============================================================================

  test "app_frame? recognises /lib/ paths as app frames (consistent with fingerprinting)" do
    assert app_frame?("file" => "/home/deploy/myapp/lib/services/payment_service.rb")
  end

  test "app_frame? recognises /config/ paths as app frames (consistent with fingerprinting)" do
    assert app_frame?("file" => "/home/deploy/myapp/config/initializers/stripe.rb")
  end

  private

  # Source preview is restricted to Rails.root — write fixtures under tmp/.
  def with_source_file(contents)
    dir = Rails.root.join("tmp")
    FileUtils.mkdir_p(dir)
    path = dir.join("backtrace_helper_test_#{SecureRandom.hex(8)}.rb")
    File.write(path, contents)
    yield path.to_s
  ensure
    FileUtils.rm_f(path) if path
  end
end
