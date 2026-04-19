# Set up gems listed in the Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

# Start SimpleCov after bundler/setup (so gem versions are locked) but before
# Bundler.require in application.rb loads any engine code. This ensures engine
# files loaded during Rails boot are tracked by Coverage.
if ENV["COVERAGE"]
  require "simplecov"
end
