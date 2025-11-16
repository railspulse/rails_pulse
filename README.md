<div align="center">
  <img src="app/assets/images/rails_pulse/rails-pulse-logo.png" alt="Rails Pulse" width="200" />

  # Rails Pulse

  **Real-time performance monitoring and debugging for Rails applications**

  ![Gem Version](https://img.shields.io/gem/v/rails_pulse)
  ![Rails Version](https://img.shields.io/badge/Rails-7.2+-blue)
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
- [Background Job Monitoring](#background-job-monitoring)
  - [Overview](#overview)
  - [Supported Adapters](#supported-adapters)
  - [Job Tracking Configuration](#job-tracking-configuration)
  - [Privacy & Security](#privacy--security)
- [Authentication](#authentication)
  - [Authentication Setup](#authentication-setup)
  - [Authentication Examples](#authentication-examples)
- [Tagging System](#tagging-system)
  - [Configuring Tags](#configuring-tags)
  - [Using Tags](#using-tags)
  - [Filtering by Tags](#filtering-by-tags)
- [Data Management](#data-management)
  - [Cleanup Strategies](#cleanup-strategies)
  - [Cleanup Configuration](#cleanup-configuration)
  - [Manual Cleanup Operations](#manual-cleanup-operations)
- [Separate Database Support](#separate-database-support)
  - [Configuration](#configuration)
  - [Database Configuration](#database-configuration)
  - [Schema Loading](#schema-loading)
- [Performance Impact](#performance-impact)
  - [Running Performance Benchmarks](#running-performance-benchmarks)
- [Testing](#testing)
- [Technology Stack](#technology-stack)
- [Advantages Over Other Solutions](#advantages-over-other-solutions)
- [License](#license)

---

## Introduction

Rails Pulse is a comprehensive performance monitoring and debugging gem that provides insights into your Rails application's health. Built as a Rails Engine, it seamlessly integrates with your existing application to capture, analyze, and visualize performance metrics without impacting your production workload.

## Features

### Performance Monitoring
- Interactive dashboard with response time charts and request analytics
- SQL query performance tracking with slow query identification
- Route-specific metrics with configurable performance thresholds
- **Background job monitoring** with execution tracking and failure analysis
- Week-over-week trend analysis with visual indicators

### Background Job Tracking
- **Universal job tracking** compatible with all ActiveJob adapters
- Monitor job performance, failures, and retries
- Track individual job executions with detailed metrics
- View operations and SQL queries executed during jobs
- Configurable privacy controls for job arguments

### Developer Experience
- Zero configuration setup with sensible defaults
- Beautiful responsive interface with dark/light mode
- Smart caching with minimal performance overhead
- Multiple database support (SQLite, PostgreSQL, MySQL)

### Organization & Filtering
- Flexible tagging system for routes, requests, queries, and jobs
- Filter performance data by custom tags
- Organize monitoring data by environment, priority, or custom categories

## Screenshots

<table>
  <tr>
    <td><img src="app/assets/images/rails_pulse/dashboard.png" alt="Rails Pulse Dashboard" width="400" /></td>
    <td><img src="app/assets/images/rails_pulse/request.png" alt="Rails Pulse Requests" width="400" /></td>
  </tr>
</table>


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
# Install with single database setup (default - recommended)
rails generate rails_pulse:install

# Or install with separate database setup
rails generate rails_pulse:install --database=separate
```

**For single database setup (default):**
```bash
rails db:migrate    # Creates Rails Pulse tables in your main database
```

**For separate database setup:**
1. Configure `config/database.yml` with your Rails Pulse database settings
2. Run: `rails db:prepare` to create and load the schema

Add the Rails Pulse route to your application:

```ruby
Rails.application.routes.draw do
  mount RailsPulse::Engine => "/rails_pulse"
end
```

Schedule background jobs:

```ruby
# Schedule to run 5 minutes past every hour. cron: 5 * * * *
RailsPulse::SummaryJob.perform_later

# Schedule to run daily. cron: 0 1 * * *
RailsPulse::CleanupJob.perform_later
```

### Quick Setup

Rails Pulse automatically starts collecting performance data once installed. Access your monitoring dashboard at:

```
http://localhost:3000/rails_pulse
```

**Database Setup:**
- **Single Database (default)**: Rails Pulse tables are created in your main database - no additional configuration needed
- **Separate Database**: See the [Separate Database Support](#separate-database-support) section for setup instructions

### Basic Configuration

Customize Rails Pulse in `config/initializers/rails_pulse.rb`:

```ruby
RailsPulse.configure do |config|
  # Enable or disable Rails Pulse
  config.enabled = true

  # Set performance thresholds for route response times (in milliseconds)
  config.route_thresholds = {
    slow: 500,
    very_slow: 1500,
    critical: 3000
  }

  # Set performance thresholds for request response times (in milliseconds)
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

  # Set performance thresholds for background jobs (in milliseconds)
  config.job_thresholds = {
    slow: 5_000,      # 5 seconds
    very_slow: 30_000, # 30 seconds
    critical: 60_000   # 1 minute
  }

  # Asset tracking configuration
  config.track_assets = false       # Ignore asset requests by default
  config.custom_asset_patterns = [] # Additional asset patterns to ignore

  # Job tracking configuration
  config.track_jobs = true          # Enable background job tracking
  config.capture_job_arguments = false # Disable argument capture for privacy

  # Rails Pulse mount path (optional)
  # Specify if Rails Pulse is mounted at a custom path to prevent self-tracking
  config.mount_path = nil  # e.g., "/admin/monitoring"

  # Route filtering - ignore specific routes from performance tracking
  config.ignored_routes = []    # Array of strings or regex patterns
  config.ignored_requests = []  # Array of request patterns to ignore
  config.ignored_queries = []   # Array of query patterns to ignore
  config.ignored_jobs = []      # Array of job class names to ignore
  config.ignored_queues = []    # Array of queue names to ignore

  # Tagging system - define available tags for categorizing performance data
  config.tags = ["production", "staging", "critical", "needs-optimization"]

  # Data cleanup
  config.archiving_enabled = true         # Enable automatic cleanup
  config.full_retention_period = 30.days  # Delete records older than this
  config.max_table_records = {            # Maximum records per table
    rails_pulse_operations: 100_000,
    rails_pulse_requests: 50_000,
    rails_pulse_job_runs: 50_000,
    rails_pulse_queries: 10_000,
    rails_pulse_routes: 1_000,
    rails_pulse_jobs: 1_000
  }

  # Multiple database support (optional)
  # Uncomment to store Rails Pulse data in a separate database
  # config.connects_to = {
  #   database: { writing: :rails_pulse, reading: :rails_pulse }
  # }
end
```

## Background Job Monitoring

Rails Pulse provides comprehensive monitoring for ActiveJob background jobs, tracking performance, failures, and execution details across all major job adapters.

### Overview

Background job monitoring is **enabled by default** and works automatically with any ActiveJob adapter. Rails Pulse captures:

- **Job execution metrics**: Duration, status, retry attempts
- **Failure tracking**: Error class, error message, failure rates
- **Performance analysis**: Slow jobs, aggregate metrics by job class
- **Operation timeline**: SQL queries and operations during job execution
- **Job arguments**: Optional capture for debugging (disabled by default for privacy)

Access the jobs dashboard at `/rails_pulse/jobs` to view:
- All job classes with aggregate metrics (total runs, failure rate, average duration)
- Individual job executions with detailed performance data
- Filtering by time range, status, queue, and performance thresholds
- Tagging support for organizing jobs by team, priority, or category

### Supported Adapters

Rails Pulse works with all ActiveJob adapters through universal tracking:

- **Sidekiq** - Enhanced tracking via custom middleware
- **Solid Queue** - Universal ActiveJob tracking
- **Good Job** - Universal ActiveJob tracking
- **Delayed Job** - Enhanced tracking via custom plugin
- **Resque** - Universal ActiveJob tracking
- **Any ActiveJob adapter** - Falls back to universal tracking

No additional configuration needed - job tracking works out of the box with your existing setup.

### Job Tracking Configuration

Customize job tracking in your Rails Pulse initializer:

```ruby
RailsPulse.configure do |config|
  # Enable or disable job tracking (default: true)
  config.track_jobs = true

  # Set performance thresholds for jobs (in milliseconds)
  config.job_thresholds = {
    slow: 5_000,        # 5 seconds
    very_slow: 30_000,  # 30 seconds
    critical: 60_000    # 1 minute
  }

  # Ignore specific job classes from tracking
  config.ignored_jobs = [
    "ActiveStorage::AnalyzeJob",
    "ActiveStorage::PurgeJob"
  ]

  # Ignore specific queues from tracking
  config.ignored_queues = ["low_priority", "mailers"]

  # Capture job arguments for debugging (default: false)
  # WARNING: May expose sensitive data - use with caution
  config.capture_job_arguments = false

  # Configure adapter-specific settings
  config.job_adapters = {
    sidekiq: { enabled: true, track_queue_depth: false },
    solid_queue: { enabled: true, track_recurring: false },
    good_job: { enabled: true, track_cron: false },
    delayed_job: { enabled: true },
    resque: { enabled: true }
  }
end
```

**Disabling job tracking for specific jobs:**

```ruby
class MyBackgroundJob < ApplicationJob
  # Skip Rails Pulse tracking for this job
  def perform(*args)
    RailsPulse.with_tracking_disabled do
      # Job logic here
    end
  end
end
```

### Privacy & Security

**Job argument capture is disabled by default** to protect sensitive information. Job arguments may contain:
- User credentials or tokens
- Personal identifiable information (PII)
- API keys or secrets
- Sensitive business data

Only enable `capture_job_arguments` in development or when explicitly needed for debugging. Consider using parameter filtering if you need to capture arguments:

```ruby
# In your job class
class SensitiveJob < ApplicationJob
  def perform(user_id:, api_key:)
    # Rails Pulse will track execution but not arguments by default
  end
end
```

**Performance impact:**
- Minimal overhead: ~1-2ms per job execution
- No blocking of job processing
- Configurable cleanup prevents database growth
- Can be disabled per-job or globally

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

#### Devise with Admin Role

```ruby
config.authentication_method = proc {
  unless user_signed_in? && current_user.admin?
    redirect_to main_app.root_path, alert: "Access denied"
  end
}
```

#### Custom Authorization Logic

```ruby
config.authentication_method = proc {
  current_user = User.find_by(id: session[:user_id])
  unless current_user&.can_access_monitoring?
    render plain: "Forbidden", status: :forbidden
  end
}
```

## Tagging System

Rails Pulse includes a flexible tagging system that allows you to categorize and organize your performance data. Tag routes, requests, queries, jobs, and job runs with custom labels to better organize and filter your monitoring data.

### Configuring Tags

Define available tags in your Rails Pulse initializer:

```ruby
RailsPulse.configure do |config|
  config.tags = [
    "production",
    "staging",
    "critical",
    "needs-optimization",
    "high-traffic",
    "background-job"
  ]
end
```

### Using Tags

**Tag from the UI:**

1. Navigate to any route, request, query, job, or job run detail page
2. Click the "+ tag" button next to the record
3. Select from your configured tags
4. Remove tags by clicking the × button on any tag badge

**Tag Programmatically:**

```ruby
# Tag a route
route = RailsPulse::Route.find_by(path: "/api/users")
route.add_tag("critical")
route.add_tag("high-traffic")

# Tag a query
query = RailsPulse::Query.find_by(normalized_sql: "SELECT * FROM users WHERE id = ?")
query.add_tag("needs-optimization")

# Tag a job
job = RailsPulse::Job.find_by(name: "UserNotificationJob")
job.add_tag("high-priority")
job.add_tag("user-facing")

# Tag a specific job run
job_run = RailsPulse::JobRun.find_by(run_id: "abc123")
job_run.add_tag("investigated")

# Remove a tag
route.remove_tag("critical")

# Check if has tag
route.has_tag?("production") # => true
```

### Filtering by Tags

Use the global filters modal to filter performance data by tags:

1. Click the filter icon in the top navigation
2. Select one or more tags from the tag selector
3. Apply filters to see only records with those tags
4. Tags appear as badges in all data tables for quick visual identification

**Common Tagging Strategies:**

- **By Environment**: `production`, `staging`, `development`
- **By Priority**: `critical`, `high`, `medium`, `low`
- **By Status**: `needs-optimization`, `investigating`, `resolved`
- **By Type**: `api`, `background-job`, `user-facing`, `admin`
- **By Team**: `team-frontend`, `team-backend`, `team-data`

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
RailsPulse::CleanupJob.perform_later
```

## Separate Database Support

Rails Pulse offers two database setup options to fit your application's needs:

### Option 1: Single Database (Default - Recommended)

Stores Rails Pulse data in your main application database alongside your existing tables. This is the simplest setup and works great for most applications.

**Advantages:**
- Zero additional configuration required
- Simpler backup and deployment strategies
- Works with any database (SQLite, PostgreSQL, MySQL)

**Installation:**
```bash
rails generate rails_pulse:install
rails db:migrate
```

### Option 2: Separate Database

Stores Rails Pulse data in a dedicated database, completely isolated from your main application.

**Use a separate database when you want:**
- **Isolating monitoring data** from your main application database
- **Using different database engines** optimized for time-series data
- **Scaling monitoring independently** from your application
- **Simplified backup strategies** with separate retention policies

### Configuration

To use a separate database, install with the `--database=separate` flag, then configure the `connects_to` option in your Rails Pulse initializer:

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

### Installation Steps

**For separate database setup:**

1. **Generate installation files:**
   ```bash
   rails generate rails_pulse:install --database=separate
   ```

2. **Configure `config/database.yml`** (see examples above)

3. **Create and load the schema:**
   ```bash
   rails db:prepare
   ```
   This automatically creates the database and loads the Rails Pulse schema.

**Schema Management:**

The schema file `db/rails_pulse_schema.rb` serves as your single source of truth for the database structure. It:
- Defines all Rails Pulse tables in one place
- Is loaded by the installation migration
- Should not be deleted or modified
- Future updates will provide migrations in `db/rails_pulse_migrate/`

## Performance Impact

Rails Pulse includes comprehensive performance monitoring with measurable overhead. Based on real benchmarking:

- **Request overhead:** 5-6ms per request (includes database writes)
- **Memory allocation:** ~830 KB per request (temporary, garbage collected)
- **Job tracking overhead:** < 0.1ms per background job
- **Relative impact:** 1-5% for typical requests (100-500ms)

**Important:** The overhead is primarily from persisting tracking data to the database. For high-traffic production applications (> 10,000 RPM), consider using aggressive filtering, sampling, or a separate database.

For detailed benchmarking methodology, optimization strategies, and how to measure Rails Pulse's impact on your specific application, see the **[Performance Impact Guide](docs/performance_impact.md)**.

### Running Performance Benchmarks

Rails Pulse includes built-in benchmarking tools. To use them:

```ruby
# Add to your Gemfile (development/test group)
gem 'benchmark-ips'
gem 'memory_profiler'
```

```bash
bundle install

# Run all benchmarks
bundle exec rake rails_pulse:benchmark:all

# Run specific benchmarks
bundle exec rake rails_pulse:benchmark:memory
bundle exec rake rails_pulse:benchmark:request_overhead
bundle exec rake rails_pulse:benchmark:middleware
```

See the **[Performance Impact Guide](docs/performance_impact.md)** for detailed instructions and interpreting results.

## Testing

Rails Pulse includes a comprehensive test suite designed for speed and reliability across multiple databases and Rails versions.

### Running the Complete Test Suite

```bash
# Run all tests (unit, functional, integration, instrumentation)
rails test:all
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
```

### Multi-Database and Rails Version Testing

Test against multiple databases and Rails versions using the matrix task:

```bash
# Test all database and Rails version combinations locally
rails test:matrix
```

This command tests all combinations locally:
- **Databases**: SQLite3, PostgreSQL, MySQL2 (local testing only)
- **Rails versions**: 7.2, 8.0

**Note**: CI only tests SQLite3 + PostgreSQL for reliability. MySQL is available for local testing but excluded from CI due to flakiness.

### Development Environment Setup

1. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure your database credentials in `.env` (for local multi-database testing):**
   ```bash
   # PostgreSQL Configuration (used in CI + local)
   POSTGRES_USERNAME=your_username
   POSTGRES_PASSWORD=your_password
   POSTGRES_HOST=localhost
   POSTGRES_PORT=5432

   # MySQL Configuration (local testing only)
   MYSQL_USERNAME=root
   MYSQL_PASSWORD=your_password
   MYSQL_HOST=localhost
   MYSQL_PORT=3306
   ```

3. **Create test databases:**
   ```bash
   # PostgreSQL
   createdb rails_pulse_test

   # MySQL
   mysql -u root -p -e "CREATE DATABASE rails_pulse_test;"
   ```

### Manual Database Testing

Test individual databases locally:

```bash
# Test with SQLite (default)
rails test:all

# Test with PostgreSQL
DB=postgresql FORCE_DB_CONFIG=true rails test:all

# Test with MySQL (local only)
DB=mysql2 FORCE_DB_CONFIG=true rails test:all
```

### CI Testing

GitHub Actions CI automatically tests:
- **Databases**: SQLite3, PostgreSQL only (MySQL excluded for reliability)
- **Rails versions**: 7.2, 8.0
- **Environment**: Uses memory SQLite and PostgreSQL service

**Local vs CI differences**:
- **Local**: Can test all 3 databases (SQLite3, PostgreSQL, MySQL2)
- **CI**: Only SQLite3 + PostgreSQL for fast, reliable builds
- **Database switching**: Requires `FORCE_DB_CONFIG=true` locally

## Technology Stack

Rails Pulse is built using modern, battle-tested technologies that ensure reliability, performance, and maintainability:

### **Frontend Technologies**
- **[CSS Zero](https://github.com/lazaronixon/css-zero)** - Modern utility-first CSS framework bundled for asset independence
- **[Stimulus](https://stimulus.hotwired.dev/)** - Progressive JavaScript framework for enhanced interactivity
- **[Turbo](https://turbo.hotwired.dev/)** - Fast navigation and real-time updates without full page reloads
- **[Turbo Frames](https://turbo.hotwired.dev/handbook/frames)** - Lazy loading and partial page updates for optimal performance

### **Data Visualization**
- **[Apache ECharts](https://echarts.apache.org/)** - Powerful, interactive charting library
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
