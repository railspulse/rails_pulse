---
name: rails-pulse
description: Investigate Rails application performance with Rails Pulse. Use when asked about slow endpoints, regressions after a deploy, expensive or N+1 SQL, error rates, failing background jobs, or whether a performance fix worked. Prefers the rails_pulse_* MCP tools; falls back to the rails-pulse CLI.
---

# Rails Pulse

Rails Pulse records every request, SQL query, background job and exception of a Rails application in the application's own database. This skill gives you read access to that data so you can find what is slow, why, and whether a change fixed it. Nothing here can modify the application.

## When to use it

- Investigating a performance complaint or a slow endpoint
- Diagnosing a regression after a deployment
- Finding expensive or N+1 SQL queries
- Investigating an increased error rate
- Analysing background job failures or slowness
- Validating whether a performance fix worked

## Interfaces

### MCP tools (preferred when available)

All tools are read-only. Each returns a `summary` and `next_steps`.

| Tool | Purpose |
|------|---------|
| `rails_pulse_routes` | Discover endpoints: request volume, latency and errors per route |
| `rails_pulse_slow_requests` | The slowest endpoints for a period |
| `rails_pulse_errors` | Recent 4xx/5xx responses grouped by endpoint |
| `rails_pulse_exceptions` | Exception groups with status, occurrence count, location and latest message |
| `rails_pulse_exception` | One group's recent occurrences with full backtraces, request, params and deploy SHA |
| `rails_pulse_endpoint` | Deep profile of one endpoint |
| `rails_pulse_queries` | Most expensive SQL queries, with N+1 detection |
| `rails_pulse_jobs` | Background job health and recent failures with error classes |
| `rails_pulse_deployments` | Recent deployments with revision, start and finish time, and metadata |

### CLI

The `rails-pulse` executable ships with the gem. Add `--json` for structured output.

| Command | Purpose |
|---------|---------|
| `rails-pulse routes list --json` | Tracked routes (add `--since` for stats) |
| `rails-pulse requests list --json` | Recorded requests with status and time filters |
| `rails-pulse queries list --json` | SQL queries (add `--since` for timing stats) |
| `rails-pulse jobs list --json` | Background jobs with lifetime stats |
| `rails-pulse job_runs list --json` | Individual job runs with error class and message |
| `rails-pulse exceptions list --json` | Exception groups with status, count, location and message |
| `rails-pulse exceptions show ID --json` | One group with backtraces, request, params and deploy SHA |
| `rails-pulse deployments list --json` | Recorded deployments, most recent first |

## Investigation workflow

### 1. Establish the time period

Check recent deployments first; a regression usually lines up with one.

```
rails_pulse_deployments(period: "last_7_days")
rails-pulse deployments list --json
```

Use a deployment's `started_at` as the `period` for the tools below, then compare against the period before it.

### 2. Identify affected endpoints

```
rails_pulse_slow_requests(period: "last_24_hours", limit: 10)
rails_pulse_routes(search: "checkout", period: "last_7_days")
rails-pulse requests list --limit 50 --json
```

### 3. Profile the suspect endpoint

```
rails_pulse_endpoint(endpoint: "CheckoutController#create", period: "last_7_days")
rails-pulse requests list --since 2026-06-01T00:00:00Z --json
```

### 4. Check errors

```
rails_pulse_errors(period: "last_24_hours", status: "5xx")
rails-pulse requests list --status 5xx --since 2026-06-01T00:00:00Z --json
```

### 5. Inspect SQL and background jobs

```
rails_pulse_queries(period: "last_24_hours", sort: "total_duration")
rails_pulse_queries(n_plus_one_only: true)
rails_pulse_jobs(period: "last_24_hours")
rails-pulse queries list --since 2026-06-01T00:00:00Z --json
rails-pulse job_runs list --status failed --json
```

### 6. Correlate with source code

Use the `controller#action` name to find the code. Look for N+1 queries, missing indexes, expensive work in the request path, unnecessary serialization and missing caching.

### 7. Fix, then validate

After the fix is deployed, re-check the same endpoint over the period since the deploy.

```
rails_pulse_deployments(period: "last_24_hours")
rails_pulse_endpoint(endpoint: "CheckoutController#create", period: "last_hour")
```

## Guidelines

- **SQL is not always the cause.** External API calls, serialization, view rendering and application logic slow requests too.
- **Use more than one tool.** Cross-reference latency with error rates, SQL timing and job performance before concluding.
- **Check the error rate.** A fast endpoint with a high error rate may be failing early rather than performing well.
- **Read percentiles, not just averages.** A low average with a high p95 or p99 means intermittent trouble.
- **Weigh request volume.** A slow endpoint nobody calls may not be worth the work.
- **Job aggregates are all-time.** `rails_pulse_jobs` counts and percentiles cover the job's whole history; only `recent_failures` is scoped to the period.

## Authentication

The CLI and MCP server read credentials from environment variables or `~/.rails-pulse`. The token is `config.api_token` in the application's Rails Pulse initializer.

```
RAILS_PULSE_URL=https://myapp.com
RAILS_PULSE_TOKEN=my-secret-token
RAILS_PULSE_MOUNT_PATH=/rails_pulse   # optional, default /rails_pulse
```

```yaml
# ~/.rails-pulse
url: https://myapp.com
token: my-secret-token
mount_path: /rails_pulse
```

Interactive setup: `rails-pulse configure`.

## CLI reference

List commands accept `--limit N` (1 to 500, default 25), `--offset N` and `--json`. Time-based commands also accept `--since TIME` and `--until TIME` as ISO 8601. JSON output is `{ "data": [...], "meta": { "total", "limit", "offset" } }`; page with `--offset`.
