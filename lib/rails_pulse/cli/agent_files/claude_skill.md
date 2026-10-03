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
| `rails_pulse_coverage` | What has been recorded, how recently, and any collection gaps |
| `rails_pulse_errors` | Recent 4xx/5xx responses grouped by endpoint |
| `rails_pulse_exceptions` | Exception groups with status, occurrence count, location and latest message |
| `rails_pulse_exception` | One group's recent occurrences with full backtraces, request, params and deploy SHA |
| `rails_pulse_endpoint` | Deep profile of one endpoint |
| `rails_pulse_queries` | Most expensive SQL queries, with N+1 detection |
| `rails_pulse_jobs` | Background job health and recent failures with error classes |
| `rails_pulse_deployments` | Recent deployments with timing, metadata, and whether each one degraded response time or error rate |

### CLI

The `rails-pulse` executable ships with the gem. Add `--json` for structured output.

| Command | Purpose |
|---------|---------|
| `rails-pulse routes list --json` | Tracked routes (add `--since` for stats) |
| `rails-pulse requests list --json` | Recorded requests with status and time filters |
| `rails-pulse queries list --json` | SQL queries (add `--since` for timing stats) |
| `rails-pulse jobs list --json` | Background jobs: lifetime stats, or one window's with `--since` / `--until` |
| `rails-pulse job_runs list --json` | Individual job runs with error class and message |
| `rails-pulse exceptions list --json` | Exception groups with status, count, location and message |
| `rails-pulse exceptions show ID --json` | One group with backtraces, request, params and deploy SHA |
| `rails-pulse deployments list --json` | Recorded deployments, most recent first, each with its before/after comparison |
| `rails-pulse coverage show --json` | What has been recorded, how recently, and any collection gaps |

## Investigation workflow

### 1. Establish the time period

Check recent deployments first; a regression usually lines up with one.

```
rails_pulse_deployments(period: "last_7_days")
rails-pulse deployments list --json
```

Each deployment carries a `comparison` of the hour before the deploy against the hour after it.
`degraded` means average or p95 response time got more than 1.5x worse, or the error rate more
than 1.25x worse; the `metrics` say which. `insufficient_data` means fewer than 10 requests in
either hour, so it is not an all-clear, and `pending` means the hour after has not been
summarized yet. Use the `before` and `after` bounds as `since`/`until` for the tools below to see
which endpoints changed.

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

Pass the endpoint's `route_id` to `rails_pulse_queries` to see only the SQL that ran inside it,
with `source_locations` naming the file and line each query was issued from.

```
rails_pulse_queries(route: 42, period: "last_24_hours")
```

Start at those locations rather than searching for the SQL. Look for N+1 queries, missing
indexes, expensive work in the request path, unnecessary serialization and missing caching.

### 7. Fix, then validate

After the fix is deployed, re-check the same endpoint over the period since the deploy.

```
rails_pulse_deployments(period: "last_24_hours")
rails_pulse_endpoint(endpoint: "CheckoutController#create", period: "last_hour")
```

To show a change rather than a snapshot, measure the same endpoint over two fixed windows
either side of the release. Every windowed tool takes `since` and `until` as ISO 8601
timestamps, read as UTC when no zone is given, and echoes the bounds it used back as `window`.

```
rails_pulse_endpoint(endpoint: "CheckoutController#create", since: "2026-09-24T12:00:00Z", until: "2026-09-25T12:00:00Z")
rails_pulse_endpoint(endpoint: "CheckoutController#create", since: "2026-09-25T12:00:00Z", until: "2026-09-26T12:00:00Z")
```

Use the deploy time as the boundary, and exclude the minutes around it when a rolling deploy
makes them a mix of both versions.

## Guidelines

- **SQL is not always the cause.** External API calls, serialization, view rendering and application logic slow requests too.
- **Use more than one tool.** Cross-reference latency with error rates, SQL timing and job performance before concluding.
- **Orient once before investigating.** `rails_pulse_coverage` names the application, environment and version you are querying. Call it first, so findings are attributed to the installation that actually produced them.
- **Confirm the data exists before reporting an all-clear.** An empty result means nothing was recorded, which only means nothing happened when collection was healthy over that window. Call `rails_pulse_coverage` before concluding a period was clean, and say so when it flags a gap, stale summaries or a kind that is not tracked.
- **Check the error rate.** A fast endpoint with a high error rate may be failing early rather than performing well.
- **Read percentiles, not just averages.** A low average with a high p95 or p99 means intermittent trouble.
- **Weigh request volume.** A slow endpoint nobody calls may not be worth the work.
- **Job figures cover the window.** `rails_pulse_jobs` reads them from summaries plus the runs not yet summarized. p95 and p99 are given only when one summary period holds the whole window; otherwise they are null and `note` says why, so compare averages and failure rates instead.
- **Check what the percentiles covered.** `rails_pulse_endpoint` computes them over the most recent requests it sampled, not the whole window. When `sampled_requests` is below `request_count` it says so in `latency.computed_over`; narrow the window until the two match before comparing percentiles across windows.

## Authentication

The CLI and MCP server read credentials from environment variables or `~/.rails-pulse`. The token is `config.api_token` in the application's Rails Pulse initializer. It is read-only: recording a deployment needs `config.deployment_token`, which these tools do not carry.

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

List commands accept `--limit N` (1 to 500, default 25), `--offset N` and `--json`. Every list command also accepts `--since TIME` and `--until TIME` as ISO 8601; a time with no zone is read as UTC. JSON output is `{ "data": [...], "meta": { "total", "limit", "offset" } }`; page with `--offset`.
