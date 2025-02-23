require_relative "lib/rails_pulse/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_pulse"
  spec.version     = RailsPulse::VERSION
  spec.authors     = [ "Rails Pulse" ]
  spec.email       = [ "hey@railspuls.com" ]
  spec.homepage    = "www.railspulse.com"
  spec.summary     = "Ruby on Rails performance monitoring tool."
  spec.description = "Ruby on Rails performance monitoring tool that provides insights into your application's performance, helping you identify bottlenecks and optimize your code for better efficiency."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0.1"
  spec.add_dependency "css-zero", ">= 1.1.4"
  spec.add_dependency "rails_charts", ">= 0.0.6"
  spec.add_dependency "lucide-rails", ">= 0.5.1"
  spec.add_dependency "turbo-rails", "~> 2.0.11"
  spec.add_dependency "request_store", "~> 1.5"
end
