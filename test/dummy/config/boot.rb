# Set up gems listed in the Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

# Start SimpleCov after bundler/setup (so gem versions are locked) but before
# Bundler.require in application.rb loads any engine code. This ensures engine
# files loaded during Rails boot are tracked by Coverage.
# NOTE: compare against "true" — CI workflows export COVERAGE="" for
# non-coverage cells, and "" is truthy in Ruby, which would start SimpleCov
# (and its minimum-coverage at_exit gate) for every job, killing db:migrate.
if ENV["COVERAGE"] == "true"
  require "simplecov"
end
