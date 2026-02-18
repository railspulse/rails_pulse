source "https://rubygems.org"

# Specify your gem's dependencies in rails_pulse.gemspec.
gemspec

gem "puma"

gem "sqlite3"
gem "pg"

# Load environment variables from .env file
gem "dotenv-rails", groups: [ :development, :test ]

gem "css-zero"
gem "importmap-rails"
gem "ransack"
gem "turbo-rails"
gem "request_store"

# Testing dependencies
group :test do
  gem "appraisal"
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "factory_bot_rails"
  gem "faker"
  gem "minitest-reporters"
  gem "mocha"
  gem "pry-byebug"
  gem "selenium-webdriver"
  gem "shoulda-matchers"
  gem "test-prof"
  gem "timecop"
end

group :development do
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-minitest", require: false

  # Security scanning
  gem "brakeman", require: false
end

group :development, :test do
  gem "benchmark-ips"
  gem "memory_profiler"
  gem "debug"
end
