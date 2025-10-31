require_relative "lib/rails_pulse/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_pulse"
  spec.version     = RailsPulse::VERSION
  spec.authors     = [ "Rails Pulse" ]
  spec.email       = [ "hey@railspulse.com" ]
  spec.homepage    = "https://www.railspulse.com"
  spec.summary     = "Ruby on Rails performance monitoring tool."
  spec.description = "Ruby on Rails performance monitoring tool that provides insights into your application's performance, helping you identify bottlenecks and optimize your code for better efficiency."
  spec.license     = "MIT"

  # Specify minimum Ruby version
  spec.required_ruby_version = ">= 3.0.0"

  # Allow pushing to RubyGems.org
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = "https://www.railspulse.com"
  spec.metadata["source_code_uri"] = "https://github.com/railspulse/rails_pulse"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib,public}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.1.0", "< 9.0.0"
  spec.add_dependency "css-zero", "~> 1.1", ">= 1.1.4"
  spec.add_dependency "rails_charts", "~> 0.0", ">= 0.0.6"
  spec.add_dependency "turbo-rails", "~> 2.0.11"
  spec.add_dependency "request_store", "~> 1.5"
  spec.add_dependency "ransack", "~> 4.0"
  spec.add_dependency "pagy", ">= 8", "< 44"
  spec.add_dependency "groupdate", "~> 6.0"

  spec.add_development_dependency "rails-controller-testing"
end
