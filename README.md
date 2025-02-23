<div align="center">
  <img src="app/assets/images/rails_pulse/rails-pulse-logo.png" alt="Rails Pulse" width="200" />

  # Rails Pulse

  **Real-time performance monitoring and debugging for Rails applications**

  ![Gem Version](https://img.shields.io/gem/v/rails_pulse)
  ![Rails Version](https://img.shields.io/badge/Rails-8.0+-blue)
  ![License](https://img.shields.io/badge/License-MIT-green)
  ![Ruby Version](https://img.shields.io/badge/Ruby-3.0+-red)
</div>

---

## Introduction

Rails Pulse is a comprehensive performance monitoring and debugging gem that provides real-time insights into your Rails application's health. Built as a Rails Engine, it seamlessly integrates with your existing application to capture, analyze, and visualize performance metrics without impacting your production workload.

**Why Rails Pulse?**

- **Zero Configuration**: Works out of the box with sensible defaults
- **Lightweight**: Minimal performance overhead in production
- **Comprehensive**: Monitors requests, database queries, and application operations
- **Visual**: Beautiful, responsive dashboards with actionable insights
- **Real-time**: Live performance metrics and health scoring

Rails Pulse helps you identify performance bottlenecks, track response times, monitor database query performance, and maintain application health with an intuitive web interface that celebrates good performance while highlighting areas for improvement.

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

Run the migrations:

```bash
rails db:migrate
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
  # Set performance thresholds
  config.response_time_thresholds = {
    fast: 100,      # ms
    moderate: 500,  # ms
    slow: 1000      # ms
  }

  # Configure query monitoring
  config.query_thresholds = {
    fast: 10,       # ms
    moderate: 50,   # ms
    slow: 100       # ms
  }

  # Set data retention (optional)
  config.data_retention_days = 30
end
```

## Features

### 🎯 **Performance Dashboard**
- Real-time health scoring with visual indicators
- Interactive charts showing response times and request volumes
- Database performance monitoring with query analysis
- Trend analysis with historical comparisons

### 📊 **Request Monitoring**
- Complete request lifecycle tracking
- Response time analysis with percentile breakdowns
- Error rate monitoring
- Route-specific performance metrics

### 🗄️ **Database Analytics**
- SQL query performance monitoring
- Slow query identification and analysis
- Database operation breakdown by type
- Query optimization recommendations

### 🔍 **Operation Insights**
- Detailed operation-level performance data
- Custom operation tracking for business logic
- Performance impact analysis
- Operation-specific thresholds

### 📈 **Advanced Analytics**
- Performance trend analysis
- Automated performance regression detection
- Health score calculation with multiple factors

### 🎨 **Beautiful Interface**
- Responsive design that works on all devices
- Dark/light mode support with system preference detection
- Accessible UI components with proper ARIA labels
- Fast, interactive charts with real-time updates

### ⚡ **Performance Optimized**
- Fast initial page loads
- Smart caching with automatic cache invalidation
- Minimal memory footprint

## Technology Stack

Rails Pulse is built using modern, battle-tested technologies that ensure reliability, performance, and maintainability:

### **Frontend Technologies**
- **[CSS Zero](https://github.com/lazaronixon/css-zero)** - Modern utility-first CSS framework for lightweight, maintainable styling
- **[Stimulus](https://stimulus.hotwired.dev/)** - Progressive JavaScript framework for enhanced interactivity
- **[Turbo](https://turbo.hotwired.dev/)** - Fast navigation and real-time updates without full page reloads
- **[Turbo Frames](https://turbo.hotwired.dev/handbook/frames)** - Lazy loading and partial page updates for optimal performance

### **Data Visualization**
- **[Rails Charts](https://github.com/railsjazz/rails_charts)** - Rails wrapper around Apache ECharts
- **[Lucide Icons](https://lucide.dev/)** - Beautiful, consistent iconography with Rails integration

### **Performance & Optimization**
- **[Request Store](https://github.com/steveklabnik/request_store)** - Thread-safe request-scoped storage for performance data
- **[Rails Caching](https://guides.rubyonrails.org/caching_with_rails.html)** - Fragment caching with smart invalidation strategies
- **[ActiveRecord Instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html)** - Built-in Rails performance monitoring hooks

### **Development & Testing**
- **[Rails Generators](https://guides.rubyonrails.org/generators.html)** - Automated installation and configuration
- **[Omakase Ruby Styling](https://github.com/rails/rubocop-rails-omakase)** - Consistent code formatting and style

## Advantages Over Other Solutions

### **vs. Application Performance Monitoring (APM) Services**
- **No External Dependencies**: Everything runs in your Rails application
- **Zero Monthly Costs**: No subscription fees or usage-based pricing
- **Data Privacy**: All performance data stays in your database
- **Customizable**: Full control over metrics, thresholds, and interface

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

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

<div align="center">
  <strong>Built with ❤️ for the Rails community</strong>

  [Documentation](https://github.com/your-repo/rails_pulse/wiki) •
  [Issues](https://github.com/your-repo/rails_pulse/issues) •
  [Contributing](CONTRIBUTING.md)
</div>
