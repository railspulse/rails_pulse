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

The dashboard is a mounted engine: it needs your app's models, routes and
`config/initializers/rails_pulse.rb` (authentication, database connection), so
the server must start from your Rails application's root directory. It loads
`config/environment.rb` from there and refuses to boot without it.

```bash
cd /path/to/your/app
RAILS_ENV=production bundle exec rackup $(bundle show rails_pulse)/lib/rails_pulse_server.ru -p 3001
```

`RAILS_ENV` matters twice: it selects the database (from `config/database.yml`
or `DATABASE_URL`, exactly as the main app does), and it decides whether
dashboard authentication is on — the default is enabled outside `development`
and `test`, so an unset `RAILS_ENV` boots an unauthenticated dashboard against
the development database.

Two environment variables are required or strongly recommended:

- `SECRET_KEY_BASE` — the server refuses to start without it; it signs the
  dashboard's session cookie.
- `RAILS_ENV=production` — see above.

The session cookie is marked `Secure` in production, so it is only sent over
HTTPS. Terminate TLS at your reverse proxy (see the nginx example below). For a
deliberately non-TLS deployment on a private network, set
`RAILS_PULSE_INSECURE_SESSION=1`.

For development against the gem's own dummy app, run the same command from the
gem root instead.

**Deployment with Kamal:**

Deploy the dashboard as an accessory using the same image as your app, so
`config/environment.rb` and your initializer are present:

```yaml
# config/deploy.yml
accessories:
  rails_pulse:
    image: your-app-image  # Same image as your main app
    host: your-server
    cmd: sh -c 'bundle exec rackup $(bundle show rails_pulse)/lib/rails_pulse_server.ru -p 3001'
    env:
      clear:
        RAILS_ENV: production
      secret:
        - SECRET_KEY_BASE
        - DATABASE_URL          # or rely on config/database.yml in the image
    port: "3001:3001"  # Map container port to host port
    healthcheck:
      path: /health
      port: 3001
      interval: 10s
      timeout: 5s
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

Rails Pulse persists tracking data on a background thread by default (`config.async = true`), so the database writes for a request do not hold up its response.

- **Production/Development:** writes happen on a background thread once the response has been built
- **Test:** writes happen inline. The generated initializer sets `config.async = false if Rails.env.test?`, and the tracker also falls back to inline writes on its own whenever it detects a transactional-test connection, because Rails shares that single connection with every thread

**Performance Impact:**
- The request thread only hands the collected data to the writer thread
- Database writes happen off the request thread
- Set `config.async = false` to write inline before the response is sent

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
