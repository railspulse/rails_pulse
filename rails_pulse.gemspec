require_relative "lib/rails_pulse/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_pulse"
  spec.version     = RailsPulse::VERSION
  spec.authors     = [ "Scott Harvey" ]
  spec.email       = [ "hey@railspulse.com" ]
  spec.homepage    = "https://railspulse.com"
  spec.summary     = "Self-hosted performance monitoring engine for Rails apps."
  spec.description = "Self-hosted performance monitoring engine for Rails apps. Tracks slow requests, N+1 queries, and SQL performance. All data stays in your own database — no third-party cloud required."
  spec.license     = "MIT"

  # Specify minimum Ruby version
  spec.required_ruby_version = ">= 3.0.0"

  # Allow pushing to RubyGems.org
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = "https://railspulse.com"
  spec.metadata["source_code_uri"] = "https://github.com/railspulse/rails_pulse"
  spec.metadata["changelog_uri"] = "https://github.com/railspulse/rails_pulse/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://railspulse.com/documentation/installation"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,exe,lib,public,vendor}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.bindir = "exe"
  spec.executables = [ "rails_pulse_server" ]

  spec.post_install_message = <<~MSG
    Rails Pulse #{RailsPulse::VERSION} installed. If upgrading, run:
      rails generate rails_pulse:upgrade && rails db:migrate
  MSG

  spec.add_dependency "rails", ">= 7.1.0", "< 9.0.0"
  spec.add_dependency "request_store", "~> 1.5"
  spec.add_dependency "ransack", "~> 4.0"
  spec.add_dependency "async", "~> 2.0"

  spec.add_development_dependency "sqlite3", ">= 1.4"
  spec.add_development_dependency "pg", ">= 1.1"
  spec.add_development_dependency "mysql2", "~> 0.5"

  spec.add_development_dependency "importmap-rails"
  spec.add_development_dependency "css-zero", "~> 1.1", ">= 1.1.4"
  spec.add_development_dependency "rails-controller-testing", ">= 1.0"
  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "ostruct"
end
