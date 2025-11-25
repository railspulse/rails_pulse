# Deployment Modes

Rails Pulse offers flexible deployment options through two independent configuration settings: **tracking mode** and **dashboard mode**.

## Configuration Overview

### Tracking Mode

Controls **how** performance data is written to the database:

- **`async` (default)**: Background threads write to database (~1-2ms overhead)
- **`sync`**: Inline writes during request (5-6ms overhead)

### Dashboard Mode

Controls **where** the dashboard UI runs:

- **Embedded**: Dashboard mounted in your app at `/rails_pulse`
- **Standalone**: Dashboard runs as separate process via `rackup lib/rails_pulse_server.ru`

## Valid Combinations

All four combinations are valid and serve different use cases:

### 1. Async + Embedded (Default - Most Common)

```ruby
RailsPulse.configure do |config|
  config.async = true              # Default
  config.mount_dashboard = true     # Default
end
```

**Use case:** Development, staging, low-to-medium traffic production

**Characteristics:**
- Dashboard lives in your app
- Non-blocking tracking
- Simplest setup
- Good for most use cases

**Access:** `https://myapp.com/rails_pulse`

### 2. Async + Standalone (Production Recommended)

```ruby
# In main app initializer:
RailsPulse.configure do |config|
  config.async = true
  config.mount_dashboard = false    # Don't mount in main app
end

# Remove from routes.rb:
# mount RailsPulse::Engine => "/rails_pulse"
```

```bash
# Run dashboard separately:
export RAILS_PULSE_DATABASE_URL="postgresql://user:pass@host/db"
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

**Use case:** High-traffic production

**Characteristics:**
- App tracks with background threads
- Dashboard runs as separate process/container
- Dashboard accessible even when app is under heavy load
- Better security isolation
- Independent scaling

**Access:** `https://pulse.myapp.com` (proxied to port 3001)

**Benefits:**
- Dashboard remains responsive during traffic spikes
- Separate resource allocation
- Enhanced security (isolate monitoring from public app)
- Dashboard doesn't scale with app instances

### 3. Sync + Embedded (Debugging)

```ruby
RailsPulse.configure do |config|
  config.async = false
  config.mount_dashboard = true
end
```

**Use case:** Local development debugging

**Characteristics:**
- Immediate data visibility
- Easier to debug tracking issues
- Higher overhead (acceptable locally)
- Blocking database writes

**Access:** `http://localhost:3000/rails_pulse`

### 4. Sync + Standalone (Rarely Used)

```ruby
# In main app:
RailsPulse.configure do |config|
  config.async = false
  config.mount_dashboard = false
end
```

```bash
# Run dashboard separately
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

**Use case:** Testing standalone dashboard setup while debugging

**Characteristics:**
- Combines sync overhead with standalone complexity
- Generally not recommended
- Might be useful for testing deployment architecture locally

## Recommendations by Environment

### Development

```ruby
RailsPulse.configure do |config|
  config.async = true              # Default, or false for debugging
  config.mount_dashboard = true    # Convenience
end
```

**Rationale:** Embedded dashboard is most convenient. Use async by default, sync only when debugging tracking issues.

### Staging

```ruby
RailsPulse.configure do |config|
  config.async = true              # Production-like performance
  config.mount_dashboard = true    # or false to test standalone setup
end
```

**Rationale:** Mirror production configuration. Use embedded unless testing standalone deployment.

### Production (< 1,000 RPM)

```ruby
RailsPulse.configure do |config|
  config.async = true
  config.mount_dashboard = true
end
```

**Rationale:** Simple setup works fine for lower traffic. Async mode keeps overhead minimal.

### Production (> 1,000 RPM or High Security Requirements)

```ruby
# Main app
RailsPulse.configure do |config|
  config.async = true
  config.mount_dashboard = false
end
```

```bash
# Standalone dashboard (separate container/process)
export RAILS_PULSE_DATABASE_URL="postgresql://..."
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

**Rationale:**
- Async tracking keeps main app fast
- Standalone dashboard remains accessible during traffic spikes
- Better security isolation
- Can apply different access controls

## Independent Variables

**Key insight:** Tracking mode and dashboard mode are completely independent:

- **Tracking mode** affects your main app's performance characteristics
- **Dashboard mode** affects how you access the UI and operational architecture

You can mix and match based on your specific needs:
- The tracking mode decision is primarily about **performance**
- The dashboard mode decision is primarily about **architecture and security**

## Switching Between Modes

### Switching Tracking Mode

No data migration needed - just change configuration:

```ruby
# From sync to async
config.async = true

# From async to sync
config.async = false
```

Restart your application for changes to take effect.

### Switching Dashboard Mode

**From Embedded to Standalone:**

1. Update configuration:
   ```ruby
   config.mount_dashboard = false
   ```

2. Remove route:
   ```ruby
   # Remove from config/routes.rb
   # mount RailsPulse::Engine => "/rails_pulse"
   ```

3. Start standalone server:
   ```bash
   bundle exec rackup lib/rails_pulse_server.ru -p 3001
   ```

4. Configure reverse proxy (nginx/etc) to route to port 3001

**From Standalone to Embedded:**

1. Update configuration:
   ```ruby
   config.mount_dashboard = true
   ```

2. Add route:
   ```ruby
   # In config/routes.rb
   mount RailsPulse::Engine => "/rails_pulse"
   ```

3. Stop standalone server

4. Restart application

## Environment Variables

You can control modes via environment variables:

```bash
# Tracking mode
export RAILS_PULSE_ASYNC=true   # or false

# In initializer:
config.async = ENV.fetch("RAILS_PULSE_ASYNC", "true") == "true"
```

```bash
# Dashboard mode (implicit - run standalone server separately)
export RAILS_PULSE_DATABASE_URL="postgresql://..."
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

## Performance Impact Summary

| Mode | Request Overhead | Database Writes | Best For |
|------|-----------------|-----------------|----------|
| Async | ~1-2ms | Background threads | Production, staging |
| Sync | ~5-6ms | During request | Debugging, development |

| Dashboard | Isolation | Complexity | Best For |
|-----------|-----------|------------|----------|
| Embedded | Same process | Low | Development, low traffic |
| Standalone | Separate process | Medium | Production, high traffic |

## Common Patterns

### Pattern 1: Simple Development Setup
```ruby
config.async = true
config.mount_dashboard = true
```

### Pattern 2: Production-Ready Architecture
```ruby
# Main app
config.async = true
config.mount_dashboard = false

# Separate dashboard container/service
# Runs: rackup lib/rails_pulse_server.ru
```

### Pattern 3: Debugging Issues
```ruby
# Temporarily switch to sync for immediate visibility
config.async = false
config.mount_dashboard = true
```

### Pattern 4: Testing Deployment
```ruby
# Use async + standalone locally to test production setup
config.async = true
config.mount_dashboard = false

# Terminal 1: Main app
./bin/dev --async

# Terminal 2: Standalone dashboard
./bin/dev --standalone
```
