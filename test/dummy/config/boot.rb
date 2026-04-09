# Start SimpleCov before any gem code is loaded so engine files are tracked.
# Must come before bundler/setup because Rake pre-loads the dummy app before
# test_helper.rb runs, which would otherwise cause engine files to be required
# before Coverage.start is called.
if ENV["COVERAGE"]
  require "simplecov"
end

# Set up gems listed in the Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
