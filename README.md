<div align="center">
  <img src="app/assets/images/rails_pulse/rails-pulse-logo.png" alt="Rails Pulse" width="200" />

  # Rails Pulse

  **Real-time performance monitoring and debugging for Rails applications**

  ![Gem Version](https://img.shields.io/gem/v/rails_pulse)
  ![Rails Version](https://img.shields.io/badge/Rails-8.0+-blue)
  ![License](https://img.shields.io/badge/License-MIT-green)
  ![Ruby Version](https://img.shields.io/badge/Ruby-3.3+-red)
</div>

---

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Screenshots](#screenshots)
- [Getting Started](#getting-started)
  - [Installation](#installation)
  - [Quick Setup](#quick-setup)
  - [Basic Configuration](#basic-configuration)
- [Authentication](#authentication)
  - [Authentication Setup](#authentication-setup)
  - [Authentication Examples](#authentication-examples)
  - [Security Considerations](#security-considerations)
- [Data Management](#data-management)
  - [Cleanup Strategies](#cleanup-strategies)
  - [Cleanup Configuration](#cleanup-configuration)
  - [Manual Cleanup Operations](#manual-cleanup-operations)
  - [How Cleanup Works](#how-cleanup-works)
- [Multiple Database Support](#multiple-database-support)
  - [Configuration](#configuration)
  - [Database Configuration](#database-configuration)
  - [Migration](#migration)
- [Testing](#testing)
- [Technology Stack](#technology-stack)
- [Advantages Over Other Solutions](#advantages-over-other-solutions)
- [License](#license)

---

## Introduction

Rails Pulse is a comprehensive performance monitoring and debugging gem that provides real-time insights into your Rails application's health. Built as a Rails Engine, it seamlessly integrates with your existing application to capture, analyze, and visualize performance metrics without impacting your production workload.

**Why Rails Pulse?**

- **Visual**: Beautiful, responsive dashboards with actionable insights
- **Comprehensive**: Monitors requests, database queries, and application operations
- **Real-time**: Live performance metrics
- **Zero Configuration**: Works out of the box with sensible defaults
- **Lightweight**: Minimal performance overhead in production
- **Asset Independent**: Pre-compiled assets work with any Rails build system
- **CSP Compliant**: Secure by default with Content Security Policy support

## Features

### 🎯 **Performance Monitoring**
- Interactive dashboard with response time charts and request analytics
- SQL query performance tracking with slow query identification
- Route-specific metrics with configurable performance thresholds
- Week-over-week trend analysis with visual indicators

### 🔒 **Production Ready**
- Content Security Policy (CSP) compliant with pre-compiled assets
- Flexible authentication system with multiple authentication methods
- Automatic data cleanup with configurable retention policies
- Zero build dependencies - works with any Rails setup

### ⚡ **Developer Experience**
- Zero configuration setup with sensible defaults
- Beautiful responsive interface with dark/light mode
- Smart caching with minimal performance overhead
- Multiple database support (SQLite, PostgreSQL, MySQL)

## Screenshots

<img src="app/assets/images/rails_pulse/dashboard.png" alt="Rails Pulse" />

## Getting Started

### Installation

Add Rails Pulse to your application's Gemfile:

```ruby
gem 'rails_pulse'
```

Install the gem:

```bash
bundle install
```

Generate the installation files:

```bash
rails generate rails_pulse:install
```

Load the database schema:

```bash
rails db:prepare
```

Add the Rails Pulse route to your application:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RailsPulse::Engine => "/rails_pulse"
  # ... your other routes
end
```

### Quick Setup

Rails Pulse automatically starts collecting performance data once installed. Access your monitoring dashboard at:

```
http://localhost:3000/rails_pulse
```

### Basic Configuration

Customize Rails Pulse in `config/initializers/rails_pulse.rb`:

```ruby
RailsPulse.configure do |config|
  # Enable or disable Rails Pulse
  config.enabled = true

  # Set performance thresholds for routes (in milliseconds)
  config.route_thresholds = {
    slow: 500,
    very_slow: 1500,
    critical: 3000
  }

  # Set performance thresholds for requests (in milliseconds)
  config.request_thresholds = {
    slow: 700,
    very_slow: 2000,
    critical: 4000
  }

  # Set performance thresholds for database queries (in milliseconds)
  config.query_thresholds = {
    slow: 100,
    very_slow: 500,
    critical: 1000
  }

  # Asset tracking configuration
  config.track_assets = false  # Ignore asset requests by default
  config.custom_asset_patterns = []  # Additional asset patterns to ignore

  # Rails Pulse mount path (optional)
  # Specify if Rails Pulse is mounted at a custom path to prevent self-tracking
  config.mount_path = nil  # e.g., "/admin/monitoring"

  # Route filtering - ignore specific routes from performance tracking
  config.ignored_routes = []    # Array of strings or regex patterns
  config.ignored_requests = []  # Array of request patterns to ignore
  config.ignored_queries = []   # Array of query patterns to ignore

  # Data cleanup
  config.archiving_enabled = true        # Enable automatic cleanup
  config.full_retention_period = 2.weeks  # Delete records older than this
  config.max_table_records = {           # Maximum records per table
    rails_pulse_requests: 10000,
    rails_pulse_operations: 50000,
    rails_pulse_routes: 1000,
    rails_pulse_queries: 500
  }

  # Metric caching for performance
  config.component_cache_enabled = true
  config.component_cache_duration = 1.day

  # Multiple database support (optional)
  # Uncomment to store Rails Pulse data in a separate database
  # config.connects_to = {
  #   database: { writing: :rails_pulse, reading: :rails_pulse }
  # }
end
```

## Authentication

Rails Pulse supports flexible authentication to secure access to your monitoring dashboard.

### Authentication Setup

Enable authentication by configuring the following options in your Rails Pulse initializer:

```ruby
# config/initializers/rails_pulse.rb
RailsPulse.configure do |config|
  # Enable authentication
  config.authentication_enabled = true

  # Where to redirect unauthorized users (optional, defaults to "/")
  config.authentication_redirect_path = "/login"

  # Define your authentication logic
  config.authentication_method = proc {
    # Your authentication logic here
  }
end
```

### Authentication Examples

Rails Pulse works with any authentication system. Here are common patterns:

#### **Devise with Admin Role**

```ruby
config.authentication_method = proc {
  unless user_signed_in? && current_user.admin?
    redirect_to main_app.root_path, alert: "Access denied"
  end
}
```

#### **Custom Session-based Authentication**

```ruby
config.authentication_method = proc {
  unless session[:user_id] && User.find_by(id: session[:user_id])&.admin?
    redirect_to main_app.login_path, alert: "Please log in as an admin"
  end
}
```

#### **HTTP Basic Authentication**

```ruby
config.authentication_method = proc {
  authenticate_or_request_with_http_basic do |username, password|
    username == ENV['RAILS_PULSE_USERNAME'] &&
    password == ENV['RAILS_PULSE_PASSWORD']
  end
}
```

#### **Warden Authentication**

```ruby
config.authentication_method = proc {
  warden.authenticate!(scope: :admin)
}
```

#### **Custom Authorization Logic**

```ruby
config.authentication_method = proc {
  current_user = User.find_by(id: session[:user_id])
  unless current_user&.can_access_monitoring?
    render plain: "Forbidden", status: :forbidden
  end
}
```

### Security Considerations

- **Production Security**: Always enable authentication in production environments
- **Admin-only Access**: Limit access to administrators or authorized personnel
- **Environment Variables**: Use environment variables for credentials, never hardcode
- **HTTPS Required**: Always use HTTPS in production when authentication is enabled
- **Regular Access Review**: Periodically review who has access to monitoring data

**Important**: The authentication method runs in the context of the Rails Pulse ApplicationController, giving you access to all standard Rails controller methods like `redirect_to`, `render`, `session`, and any methods from your host application's authentication system.

## Data Management

Rails Pulse provides data cleanup to prevent your monitoring database from growing indefinitely while preserving essential performance insights.

### Cleanup Strategies

**Time-based Cleanup**
- Automatically delete performance records older than a specified period
- Configurable retention period (default: 2 days)
- Keeps recent data for debugging while removing historical noise

**Count-based Cleanup**
- Enforce maximum record limits per table
- Prevents any single table from consuming excessive storage
- Configurable limits for each Rails Pulse table

### Cleanup Configuration

```ruby
RailsPulse.configure do |config|
  # Enable or disable automatic cleanup
  config.archiving_enabled = true

  # Time-based retention
  config.full_retention_period = 2.weeks

  # Count-based retention - maximum records per table
  config.max_table_records = {
    rails_pulse_requests: 10000,    # HTTP requests
    rails_pulse_operations: 50000,  # Operations within requests
    rails_pulse_routes: 1000,       # Unique routes
    rails_pulse_queries: 500        # Normalized SQL queries
  }
end
```

### Manual Cleanup Operations

**Run cleanup manually:**
```bash
rails rails_pulse:cleanup
```

**Check current database status:**
```bash
rails rails_pulse:cleanup_stats
```

**Schedule automated cleanup:**
```ruby
# Using whenever gem or similar scheduler
RailsPulse::CleanupJob.perform_later
```

### How Cleanup Works

1. **Time-based Phase**: Delete all records older than `full_retention_period`
2. **Count-based Phase**: If tables still exceed limits, delete oldest remaining records
3. **Safe Deletion**: Respects foreign key constraints (operations → requests → queries/routes)
4. **Comprehensive Logging**: Detailed cleanup statistics and operation logs

This two-phase approach ensures you keep the most valuable recent performance data while maintaining manageable database sizes.

## Multiple Database Support

Rails Pulse supports storing performance monitoring data in a separate database. This is particularly useful for:

- **Isolating monitoring data** from your main application database
- **Using different database engines** optimized for time-series data
- **Scaling monitoring independently** from your application
- **Simplified backup strategies** with separate retention policies

### Configuration

To use a separate database, configure the `connects_to` option in your Rails Pulse initializer:

```ruby
RailsPulse.configure do |config|
  # Single separate database
  config.connects_to = {
    database: { writing: :rails_pulse, reading: :rails_pulse }
  }

  # Or primary/replica configuration
  config.connects_to = {
    database: { writing: :rails_pulse_primary, reading: :rails_pulse_replica }
  }
end
```

### Database Configuration

Add the corresponding database configurations to your `config/database.yml`:

```yaml
# For SQLite
production:
  # ... your main database ...
  rails_pulse:
    adapter: sqlite3
    database: storage/rails_pulse_production.sqlite3
    migrations_paths: db/rails_pulse_migrate
    pool: 5
    timeout: 5000

# For PostgreSQL
production:
  # ... your main database ...
  rails_pulse:
    adapter: postgresql
    database: myapp_rails_pulse_production
    username: rails_pulse_user
    password: <%= Rails.application.credentials.dig(:rails_pulse, :database_password) %>
    host: localhost
    migrations_paths: db/rails_pulse_migrate
    pool: 5

# For MySQL
production:
  # ... your main database ...
  rails_pulse:
    adapter: mysql2
    database: myapp_rails_pulse_production
    username: rails_pulse_user
    password: <%= Rails.application.credentials.dig(:rails_pulse, :database_password) %>
    host: localhost
    migrations_paths: db/rails_pulse_migrate
    pool: 5
```

### Schema Loading

When using a separate database, Rails Pulse uses a schema-based approach similar to solid_queue:

```bash
# Load Rails Pulse schema on the configured database
rails db:prepare

# This will automatically load the Rails Pulse schema
# alongside your main application schema
```

The installation command creates `db/rails_pulse_schema.rb` containing all the necessary table definitions. This schema-based approach provides:

- **Clean Installation**: No migration clutter in new Rails apps
- **Database Flexibility**: Easy separate database configuration  
- **Version Compatibility**: Schema adapts to your Rails version automatically
- **Future Migrations**: Schema changes will come as regular migrations when needed

**Note:** Rails Pulse maintains full backward compatibility. If no `connects_to` configuration is provided, all data will be stored in your main application database as before.

## Testing

Rails Pulse includes a comprehensive test suite designed for speed and reliability across multiple databases (SQLite, MySQL, PostgreSQL) and Rails versions.

### Running the Complete Test Suite

```bash
# Run all tests (unit, functional, integration)
rails test:all

# Run tests with speed optimizations
rails test:fast
```

### Running Individual Test Types

```bash
# Unit tests (models, helpers, utilities)
rails test:unit

# Functional tests (controllers, views)
rails test:functional

# Integration tests (end-to-end workflows)
rails test:integration
```

### Running Individual Test Files

```bash
# Run a specific test file
rails test test/models/rails_pulse/request_test.rb

# Run controller tests
rails test test/controllers/rails_pulse/dashboard_controller_test.rb

# Run helper tests
rails test test/helpers/rails_pulse/application_helper_test.rb

# Run factory verification tests
rails test test/factories_test.rb
```

### Multi-Rails Version Testing

Test against multiple Rails versions using Appraisal:

```bash
# Install dependencies for all Rails versions
bundle exec appraisal install

# Run tests against all Rails versions
bundle exec appraisal rails test:all

# Run tests against specific Rails version
bundle exec appraisal rails-7-1 rails test:unit
```

### Test Performance Features

- **In-memory SQLite**: Unit and functional tests use fast in-memory databases
- **Transaction rollback**: Tests use database transactions for fast cleanup
- **Stubbed dependencies**: External calls and expensive operations are stubbed
- **Parallel execution**: Tests run in parallel when supported

### Database Testing

Rails Pulse supports testing with multiple database adapters using simplified Rake tasks:

```bash
# Quick Commands (Recommended)
rails test:sqlite        # Test with SQLite (default)
rails test:postgresql    # Test with PostgreSQL
rails test:mysql         # Test with MySQL

# Test Matrix (before pushing)
rails test:matrix        # Test SQLite + PostgreSQL
rails test:matrix_full   # Test all databases (SQLite + PostgreSQL + MySQL)
```

#### Development Environment Setup

1. **Set up git hooks (optional but recommended):**
   ```bash
   ./scripts/setup-git-hooks
   ```
   This installs a pre-commit hook that runs RuboCop before each commit.

2. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

3. **Configure your database credentials in `.env`:**
   ```bash
   # PostgreSQL Configuration
   POSTGRES_USERNAME=your_username
   POSTGRES_PASSWORD=your_password
   POSTGRES_HOST=localhost
   POSTGRES_PORT=5432

   # MySQL Configuration
   MYSQL_USERNAME=root
   MYSQL_PASSWORD=your_password
   MYSQL_HOST=localhost
   MYSQL_PORT=3306
   ```

4. **Create test databases:**
   ```bash
   # PostgreSQL
   createdb rails_pulse_test

   # MySQL
   mysql -u root -p -e "CREATE DATABASE rails_pulse_test;"
   ```

#### Manual Commands
If you prefer the explicit approach:

```bash
# Test with SQLite (default, uses in-memory database)
rails test:all

# Test with PostgreSQL (requires local PostgreSQL setup)
DATABASE_ADAPTER=postgresql FORCE_DB_CONFIG=true rails test:all

# Test with MySQL (requires MySQL setup and mysql2 gem compilation)
DATABASE_ADAPTER=mysql FORCE_DB_CONFIG=true rails test:all
```

**Note**: Database switching is disabled by default for stability. The Rake tasks automatically handle the `FORCE_DB_CONFIG=true` requirement.

**MySQL Testing**: MySQL testing requires:
- MySQL server running locally with a `rails_pulse_test` database
- Successful compilation of the `mysql2` gem (may require system dependencies like `zstd`)
- CI environments come pre-configured, but local setup may require additional dependencies

### Quick Testing Before Push
```bash
# Recommended: Test the same databases as CI
rails test:matrix
```

## Technology Stack

Rails Pulse is built using modern, battle-tested technologies that ensure reliability, performance, and maintainability:

### **Frontend Technologies**
- **[CSS Zero](https://github.com/lazaronixon/css-zero)** - Modern utility-first CSS framework bundled for asset independence
- **[Stimulus](https://stimulus.hotwired.dev/)** - Progressive JavaScript framework for enhanced interactivity
- **[Turbo](https://turbo.hotwired.dev/)** - Fast navigation and real-time updates without full page reloads
- **[Turbo Frames](https://turbo.hotwired.dev/handbook/frames)** - Lazy loading and partial page updates for optimal performance

### **Data Visualization**
- **[Rails Charts](https://github.com/railsjazz/rails_charts)** - Rails wrapper around Apache ECharts
- **[Lucide Icons](https://lucide.dev/)** - Beautiful, consistent iconography with pre-compiled SVG bundle

### **Asset Management**
- **Pre-compiled Assets** - All CSS, JavaScript, and icons bundled into the gem
- **CSP-Safe Implementation** - Secure DOM methods and nonce-based asset loading
- **Build System** - Node.js-based build process for asset compilation
- **Zero External Dependencies** - Self-contained assets work with any Rails build system

### **Performance & Optimization**
- **[Request Store](https://github.com/steveklabnik/request_store)** - Thread-safe request-scoped storage for performance data
- **[Rails Caching](https://guides.rubyonrails.org/caching_with_rails.html)** - Fragment caching with smart invalidation strategies
- **[ActiveRecord Instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html)** - Built-in Rails performance monitoring hooks

### **Development & Testing**
- **[Rails Generators](https://guides.rubyonrails.org/generators.html)** - Automated installation and configuration
- **[Omakase Ruby Styling](https://github.com/rails/rubocop-rails-omakase)** - Consistent code formatting and style

## Advantages Over Other Solutions

### **vs. Application Performance Monitoring (APM) Services**
- **No External Dependencies**: Everything runs in your Rails application with pre-compiled assets
- **Zero Monthly Costs**: No subscription fees or usage-based pricing
- **Data Privacy**: All performance data stays in your database(s)
- **Customizable**: Full control over metrics, thresholds, and interface
- **Asset Independence**: Works with any Rails build system (Sprockets, esbuild, Webpack, Vite)

### **vs. Built-in Rails Logging**
- **Visual Interface**: Beautiful dashboards instead of log parsing
- **Structured Data**: Queryable metrics instead of text logs
- **Historical Analysis**: Persistent storage with trend analysis
- **Real-time Monitoring**: Live updates and health scoring

### **vs. Custom Monitoring Solutions**
- **Batteries Included**: Complete monitoring solution out of the box
- **Proven Architecture**: Built on Rails best practices
- **Community Driven**: Open source with active development
- **Professional Design**: Production-ready interface

### **Key Differentiators**
- **Rails-Native**: Designed specifically for Rails applications
- **Developer Experience**: Optimized for debugging and development
- **Positive Focus**: Celebrates good performance alongside problem identification
- **Contextual Insights**: Deep Rails framework integration for meaningful metrics
- **Security First**: CSP-compliant by default with secure asset handling
- **Zero Build Dependencies**: Pre-compiled assets work with any Rails setup
- **Flexible Data Storage**: Support for multiple database backends (SQLite, PostgreSQL, MySQL)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

<div align="center">
  <strong>Built with ❤️ for the Rails community</strong>

  [Documentation](https://github.com/railspulse/rails_pulse/wiki) •
  [Issues](https://github.com/railspulse/rails_pulse/issues) •
  [Contributing](CONTRIBUTING.md)
</div>
