# Rails Pulse — Agent Integration

Rails Pulse gives AI coding agents read access to a Rails application's performance data: requests, SQL queries, background jobs, exceptions and deployments, all from the application's own database. Two interfaces, one token.

## MCP server

```
rails-pulse mcp
```

The server needs the `mcp` gem, which Rails Pulse does not depend on: add `gem "mcp", "~> 1.0"` to the application's Gemfile (a development group is enough), or `gem install mcp` when running `rails-pulse` outside Bundler.

**Claude Code** (`~/.claude.json`):
```json
{
  "mcpServers": {
    "rails-pulse": {
      "command": "rails-pulse",
      "args": ["mcp"],
      "env": {
        "RAILS_PULSE_URL": "https://myapp.com",
        "RAILS_PULSE_TOKEN": "your-token"
      }
    }
  }
}
```

**Cursor** (`.cursor/mcp.json`):
```json
{
  "mcpServers": {
    "rails-pulse": { "command": "rails-pulse", "args": ["mcp"] }
  }
}
```

### Tools

All tools are read-only. Each returns a `summary` and `next_steps`.

| Tool | Purpose |
|------|---------|
| `rails_pulse_routes` | Discover endpoints with request volume, latency and errors |
| `rails_pulse_slow_requests` | Slowest endpoints for a period |
| `rails_pulse_coverage` | What has been recorded, how recently, and any collection gaps |
| `rails_pulse_errors` | Recent errors grouped by endpoint |
| `rails_pulse_exceptions` | Exception groups with status, count, location and latest message |
| `rails_pulse_exception` | One group's recent occurrences with backtraces, request and params |
| `rails_pulse_endpoint` | Deep performance profile of one endpoint |
| `rails_pulse_queries` | Most expensive SQL queries with N+1 detection |
| `rails_pulse_jobs` | Background job health and recent failures |
| `rails_pulse_deployments` | Recent deployments with revision, timing and metadata |

Every tool that takes a `period` also takes `since` and `until` as ISO 8601 timestamps, read as UTC when no zone is given, and echoes the bounds it measured back as `window`. `period` itself is only `last_hour`, `last_24_hours` or `last_7_days` (plus `all` on `rails_pulse_exceptions`); any other window is `since`/`until`. Use them to compare two fixed windows — the 24 hours before a release against the 24 hours after — rather than a relative period that moves between calls.

## CLI

The `rails-pulse` CLI works without MCP. Append `--json` for structured output.

| Command | Description |
|---------|-------------|
| `rails-pulse routes list` | Tracked routes (`--since` adds request stats) |
| `rails-pulse requests list` | Recorded requests with status and time filters |
| `rails-pulse queries list` | SQL queries (`--since` adds timing stats) |
| `rails-pulse jobs list` | Background jobs: lifetime stats, or one window's with `--since` / `--until` |
| `rails-pulse job_runs list` | Individual job runs with errors |
| `rails-pulse exceptions list` | Exception groups with status and occurrence counts |
| `rails-pulse exceptions show ID` | One group with backtraces and recent occurrences |
| `rails-pulse deployments list` | Recorded deployments, most recent first |
| `rails-pulse coverage show` | What has been recorded, how recently, and any collection gaps |

Common flags on every list command: `--limit N` (1 to 500, default 25), `--offset N`, `--json`, `--since TIME` / `--until TIME` (ISO 8601; no zone means UTC).

## Authentication

Set `RAILS_PULSE_URL` and `RAILS_PULSE_TOKEN` (the application's `config.api_token`), or run `rails-pulse configure` to write `~/.rails-pulse`. That token is read-only; recording a deployment needs `config.deployment_token`, which these tools do not carry.

## Investigation pattern

1. Pin the time window to a deployment (`rails_pulse_deployments`)
2. Identify slow or failing endpoints (`rails_pulse_slow_requests`); resolve names with `rails_pulse_routes`
3. Profile the suspect endpoint (`rails_pulse_endpoint`)
4. Check errors (`rails_pulse_errors`)
5. Inspect SQL and jobs (`rails_pulse_queries`, `rails_pulse_jobs`)
6. Correlate with source code: pass the endpoint's `route_id` to `rails_pulse_queries` for the SQL inside it and the file and line each query came from
7. Fix, deploy, and re-check the same endpoint
