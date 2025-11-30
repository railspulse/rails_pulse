# Deployment Modes

Rails Pulse offers flexible deployment options for the dashboard UI. Choose the mode that best fits your infrastructure and performance requirements.

## Dashboard Deployment Options

### Embedded Mode (Development/Staging)

The dashboard runs within your main Rails application process.

**Configuration:**

```ruby
# config/initializers/rails_pulse.rb
RailsPulse.configure do |config|
  config.mount_dashboard = true  # Default
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RailsPulse::Engine => "/rails_pulse"
  # ... your other routes
end
```

**Access:** `https://myapp.com/rails_pulse`

**Use cases:**
- Development and testing environments
- Staging servers
- Low-to-medium traffic production apps
- Simple deployments where isolation isn't critical

**Advantages:**
- ✅ Zero additional infrastructure
- ✅ Same authentication/session as main app
- ✅ Simplest setup

**Disadvantages:**
- ❌ Dashboard shares resources with main app
- ❌ Dashboard unavailable if main app is down
- ❌ Scales with app instance count

---

### Standalone Mode (Production Recommended)

The dashboard runs as a separate Rack application process.

**Main App Configuration:**

```ruby
# config/initializers/rails_pulse.rb
RailsPulse.configure do |config|
  config.mount_dashboard = false  # Disable embedded dashboard
end
```

**Standalone Server:**

```bash
# Run the standalone dashboard server
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

**Database Connection:**

The standalone server reads from the same database as your main app. Two configuration options:

1. **DATABASE_URL environment variable:**
   ```bash
   export DATABASE_URL="postgresql://user:pass@host/db"
   bundle exec rackup lib/rails_pulse_server.ru -p 3001
   ```

2. **config/database.yml (automatic):**
   - The server looks for a `rails_pulse` database connection in `config/database.yml`
   - Falls back to the primary connection if `rails_pulse` is not found
   - No environment variable needed

**Deployment with Kamal:**

Deploy the dashboard as an accessory (similar to Sidekiq or SolidQueue):

```yaml
# config/deploy.yml
accessories:
  rails_pulse:
    image: your-app-image
    host: your-server
    cmd: bundle exec rackup lib/rails_pulse_server.ru -p 3001
    env:
      clear:
        DATABASE_URL: "postgresql://user:pass@host/db"
    directories:
      - data:/data
    healthcheck:
      path: /health
      port: 3001
      interval: 10s
```

**Nginx Configuration:**

```nginx
server {
    server_name pulse.myapp.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Use cases:**
- Production environments
- High-traffic applications
- When you need dashboard isolation
- When dashboard needs independent scaling

**Advantages:**
- ✅ Dashboard remains accessible if main app is under load
- ✅ Separate resource allocation
- ✅ Enhanced security isolation
- ✅ Independent scaling
- ✅ Healthcheck endpoint for orchestration tools

**Disadvantages:**
- ❌ Requires additional process/container
- ❌ Separate authentication setup
- ❌ Slightly more complex deployment

---

## Tracking Behavior

Rails Pulse uses **async tracking** by default in all environments for minimal performance overhead:

- **Production/Development:** Uses fiber-based async tracking (via `async` gem)
- **Test:** Runs synchronously for predictability and easier debugging

This is handled automatically and requires no configuration.

**Performance Impact:**
- Async mode: ~0.1ms overhead per request
- Database writes happen in background fibers
- Non-blocking for request processing

---

## Healthcheck Endpoint

The standalone dashboard includes a healthcheck endpoint at `/health`:

**Response when healthy (200 OK):**
```json
{
  "status": "ok",
  "mode": "dashboard",
  "database": "connected",
  "timestamp": "2025-11-30T12:00:00Z"
}
```

**Response when unhealthy (503 Service Unavailable):**
```json
{
  "status": "unhealthy",
  "mode": "dashboard",
  "database": "disconnected",
  "timestamp": "2025-11-30T12:00:00Z"
}
```

Use this endpoint with:
- Kamal healthchecks
- Docker/Kubernetes liveness probes
- Load balancer health checks
- Monitoring systems

---

## Recommendation by Environment

| Environment | Recommended Mode | Rationale |
|-------------|-----------------|-----------|
| Development | Embedded | Simplicity, immediate access |
| Test | Embedded | Easier test setup |
| Staging | Embedded or Standalone | Depends on production similarity goals |
| Production (< 10 req/s) | Embedded | Simple deployment acceptable |
| Production (> 10 req/s) | Standalone | Better isolation and reliability |
| Production (High Traffic) | Standalone | Critical for dashboard availability |

---

## Migration from Embedded to Standalone

1. **Deploy standalone server** (no changes to main app yet):
   ```bash
   bundle exec rackup lib/rails_pulse_server.ru -p 3001
   ```

2. **Verify dashboard works** at standalone URL

3. **Update main app config**:
   ```ruby
   config.mount_dashboard = false
   ```

4. **Deploy main app changes**

5. **Update documentation/bookmarks** with new dashboard URL

This allows zero-downtime migration.
