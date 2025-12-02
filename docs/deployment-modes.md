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

**Important:** When `mount_dashboard = false`, you should also remove (or comment out) the `mount RailsPulse::Engine` line from your `config/routes.rb` to prevent the engine from being accessible through your main app. The `mount_dashboard` setting controls whether RailsPulse initializes dashboard-related middleware and assets, while the routes mounting controls URL accessibility.

```ruby
# config/routes.rb - Comment this out for standalone mode
# mount RailsPulse::Engine => "/rails_pulse"
```

**Standalone Server:**

The standalone server can run from either:
- **Your Rails app directory** (recommended): Has access to your `config/database.yml`
- **Rails Pulse gem directory**: For development/testing

```bash
# From your Rails app directory
bundle exec rackup lib/rails_pulse_server.ru -p 3001

# Or from the Rails Pulse gem directory (for development)
cd vendor/bundle/ruby/*/gems/rails_pulse-*
bundle exec rackup lib/rails_pulse_server.ru -p 3001
```

**Database Connection:**

The standalone server needs to connect to the same database as your main app. It supports two configuration methods (in priority order):

**Option 1: DATABASE_URL environment variable (recommended for production)**
   ```bash
   export DATABASE_URL="postgresql://user:pass@host/db"
   bundle exec rackup lib/rails_pulse_server.ru -p 3001
   ```

**Option 2: config/database.yml (recommended for development)**

   When running from your Rails app directory, the server automatically reads `config/database.yml`:
   - First looks for a `rails_pulse` connection in your current environment
   - Falls back to the primary connection if `rails_pulse` is not defined
   - Respects `RAILS_ENV` (defaults to `production`)

   Example `config/database.yml`:
   ```yaml
   production:
     primary:
       adapter: postgresql
       database: myapp_production
       # ... other settings

     # Optional: Dedicated connection for Rails Pulse
     rails_pulse:
       adapter: postgresql
       database: myapp_production  # Same database, but isolated connection pool
       # ... other settings
   ```

**Important:** The server will fail to start if neither DATABASE_URL nor config/database.yml is available.

**Deployment with Kamal:**

Deploy the dashboard as an accessory

```yaml
# config/deploy.yml
accessories:
  rails_pulse:
    image: your-app-image  # Same image as your main app
    host: your-server
    cmd: bundle exec rackup lib/rails_pulse_server.ru -p 3001
    env:
      clear:
        DATABASE_URL: "postgresql://user:pass@host/db"
        RAILS_ENV: production
        # Optional: Secret for session cookies (defaults to random value)
        SECRET_KEY_BASE: <%= ENV.fetch("SECRET_KEY_BASE") %>
    port: "3001:3001"  # Map container port to host port
    healthcheck:
      path: /health
      port: 3001
      interval: 10s
      timeout: 5s
```

**Alternative Kamal config using database.yml:**

If your app image includes `config/database.yml`, you can omit DATABASE_URL:

```yaml
accessories:
  rails_pulse:
    image: your-app-image
    host: your-server
    cmd: bundle exec rackup lib/rails_pulse_server.ru -p 3001
    env:
      clear:
        RAILS_ENV: production
        SECRET_KEY_BASE: <%= ENV.fetch("SECRET_KEY_BASE") %>
    port: "3001:3001"
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

The standalone dashboard includes a healthcheck endpoint at `/health` that verifies database connectivity.

**Testing the healthcheck:**
```bash
curl http://localhost:3001/health
```

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

**Use this endpoint with:**
- Kamal healthcheck configuration
- Docker/Kubernetes liveness and readiness probes
- Load balancer health checks
- External monitoring systems (Pingdom, UptimeRobot, etc.)

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
