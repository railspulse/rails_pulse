# Public API

Rails Pulse follows [Semantic Versioning](https://semver.org/) starting at 1.0. This page
lists the public surface: what a host application, the `rails-pulse` CLI, the MCP server, and
anything built on top of the gem are meant to depend on, and what contract each entry carries
between minor releases.

Everything not listed here is internal — `RailsPulse::Cards::*`, `Charts::*`, `Tables::*`,
controllers, concerns, `Tracker` internals below `.stats`/`.flush!`, and any other class or
method not named on this page. Internal code can change shape in a minor release; the entries
below cannot, except across a major version.

## Configuration

`RailsPulse.configure { |config| ... }` yields a `RailsPulse::Configuration` instance and
validates it on the block's return, raising `ArgumentError` for an invalid setting.

Every configuration key (~45, covering thresholds, retention, authentication, job tracking,
tags, and more) is documented inline in the install template —
`lib/generators/rails_pulse/templates/rails_pulse.rb` — which is also what an existing
installation's initializer is synced against on upgrade. That file is the source of truth for
what each key does and its default; this page does not duplicate it.

- `RailsPulse.configuration` — the current `Configuration` instance.
- `RailsPulse.logger` — the logger Rails Pulse writes to: `config.logger` if set, otherwise
  `Rails.logger` tagged `"RailsPulse"`, falling back to `Logger.new($stdout)` before Rails has
  booted a logger.
- `RailsPulse.connects_to` — `config.connects_to`, or `nil` when unset or unconfigured.

## Navigation

- `RailsPulse.register_nav_item(label:, path_helper:, icon:, position: 100)` — adds an entry
  to the dashboard sidebar, sorted by `position` ascending. Intended for a host or plugin to
  add pages without forking the layout.
- `RailsPulse.nav_items` — the registered items in sort order.

## JSON API

A read-only, token-authenticated API under `/rails_pulse/api/v1`, for the `rails-pulse` CLI,
the MCP server, CI scripts, and anything else that wants Rails Pulse data outside the
dashboard. It never consults the dashboard session — only `config.api_token` — and with no
token configured every request is refused (`401`). Send the token as an `X-Rails-Pulse-Token`
header.

- `GET routes`, `GET requests`, `GET queries`, `GET jobs`, `GET job_runs`, `GET exceptions`,
  `GET deployments` —
  index-only, paginated (`limit`, default 25, max 500; `offset`) and filterable by `since`/
  `until` (ISO 8601). Response shape is `{ data: [...], meta: { total:, limit:, offset: } }`.
  `requests` also takes `route` (substring of the controller action or route path) and
  `status` (`500` or `5xx`); `jobs` and `job_runs` take `job` (exact class name); `exceptions`
  lists exception groups filtered by `status` (`open`, `resolved`, `ignored`), `search` (substring of
  the class or location), and `sort` (`last_seen_at`, `first_seen_at`, `occurrence_count`), with
  `since`/`until` applied to when the group was last seen. `GET exceptions/:id` is the one show
  action: the group plus its most recent occurrences (`occurrences`, default 5, max 20), each with
  backtrace, request method, URL, filtered params, environment and deploy SHA; an unknown id is a
  `404`. An
  unrecognised `sort`, `status`, `since` or `until` is a `400` with the accepted values.
  `since`/`until` must be ISO 8601 (a date or a date and time; one with no zone is read as
  UTC), and an `until` not later than `since` is a `400`, as is a repeated parameter or a
  paging value that is not a whole number. Every listing breaks ties on id, so offset pages are
  stable.
  Substring filters match `_`, `%` and `!` literally.
- `queries` takes `route` — a route id, or a controller action or path to match on — and
  restricts the SQL to operations issued while serving that endpoint, which is how a caller
  gets from "this endpoint is slow" to "this is the SQL inside it". It implies a window the
  way `sort` does. Each query's `stats.source_locations` names the file and line it was issued
  from, most frequent first.
- `GET capabilities` reports the Rails Pulse version and the application name and environment
  that answered, so numbers gathered against staging are not read as production. The
  `rails_pulse_coverage` tool and `rails-pulse coverage show` fold it into their own output,
  so orientation is one call.
- `GET coverage` answers whether the data is there rather than a question about the data:
  the oldest and newest request, job run and exception held with their counts, how far hourly
  summaries have been generated and whether they are stale, what retention keeps, and the
  writer's live count, queue depth and requests dropped in the last hour with
  `collection.gap_suspected`, which is set by dropped requests alone: a writer starts with a
  process's first tracked request, so one that has gone quiet means nothing was queued, and
  the note says so rather than reporting a gap. It is what distinguishes "no failures recorded" from "no data
  captured"; a kind that is not being tracked (`config.enabled`, `track_jobs`,
  `track_exceptions`) says so instead of reporting zero, and with `config.async = false` the
  collection section says there is no writer to report rather than suspecting a gap.
- `jobs` answers a `since`/`until` window from the per-job summaries rather than the lifetime
  counters cached on the job row, plus the raw runs recorded since the last summarized period.
  Windowed figures are in each row's `stats`; the top-level counters stay lifetime totals, and
  `status=failed` keeps jobs that failed inside the window. `meta.window` reports the bounds
  actually read (widened to the period boundaries it touches, in `config.time_zone`), the
  summary granularity, `summarized_through`, and `live_from` when recent runs were counted raw.
  A window that starts before `config.hourly_summary_retention` is read from daily rows for its
  whole length. Percentiles appear only when one summarized period holds every run in the
  window — they cannot be combined across periods — and `stats.percentiles_note` says so
  otherwise.
- `routes` takes `min_requests` when a time window is given: routes with fewer requests in
  the window are excluded in SQL, before `limit`, so a busy route ranked below the limit is
  still returned. When it is above 1 the response's `meta` carries `min_requests` and
  `routes_with_traffic`, which separate "nothing ran in this window" from "nothing ran often
  enough".
- `POST deployments` and `PUT deployments/finish` are the existing endpoints CI calls to
  record a release (the same action as the `rails_pulse:record_deployment` and
  `rails_pulse:finish_deployment` rake tasks below). They sit outside the `api/v1` read-only
  scope and are the only writes in the API. They accept `config.deployment_token` alone and
  fall back to the dashboard authentication only when it is unset; `config.api_token` is
  refused, so a token handed to a coding agent cannot record a release.
- `deployment_api_token` is the pre-0.5 name for `config.deployment_token`; the alias still
  works and still authorizes deployment writes only, which is all it ever granted. A host that
  wants one credential for both sets `api_token` and `deployment_token` to the same value.

## CLI

The `rails-pulse` executable (`lib/rails_pulse/cli/`) is a Thor app that talks to the JSON API
over HTTP — it never loads the Rails app or the engine, so nothing under `lib/rails_pulse/cli/`
may reference Rails, models, or configuration directly. `rails-pulse configure` prompts for a
URL and token and writes `~/.rails-pulse`; credentials otherwise come from `RAILS_PULSE_URL`
and `RAILS_PULSE_TOKEN`. Each API resource above has a matching subcommand
(`routes`, `requests`, `queries`, `jobs`, `job_runs`, `exceptions`, `deployments`, `coverage`).
`rails-pulse install claude` writes an agent skill file to
`~/.claude/skills/rails-pulse/SKILL.md`; `rails-pulse install agents` writes a
framework-neutral descriptor to `./AGENTS.md`, and with `--append` adds a delimited Rails
Pulse section to an existing one, which a later `--append` replaces in place rather than
duplicating.

## MCP server

`rails-pulse mcp` (`lib/rails_pulse/mcp/`) starts an MCP server over stdio for AI coding
agents, built on the same HTTP client as the CLI. It needs the `mcp` gem, which is a
development dependency of this gem and not a runtime one: the host adds `gem "mcp"` to its
own Gemfile, and without it the command exits 1 saying so. All ten tools are read-only
(`read_only_hint: true`) and named `rails_pulse_<resource>`: `routes`, `endpoint`, `queries`,
`errors`, `exceptions`, `exception`, `jobs`, `slow_requests`, `deployments`, and `coverage`.

Every tool that takes a `period` also takes `since` and `until` as ISO 8601 timestamps, so a
window can be pinned rather than measured relative to now — what makes a before/after-deploy
comparison repeatable. A timestamp with no zone is read as UTC. Explicit bounds win over
`period`, and each tool echoes what it measured as `window: { since:, until:, period: }`.
`period` takes only `last_hour`, `last_24_hours` or `last_7_days` (and `all` on
`rails_pulse_exceptions`); any other window is `since`/`until`. A timestamp that is not ISO
8601, an unknown period, a `since` in the future, or an `until` at or before `since` is an
error naming the correction rather than a query. `rails_pulse_queries` takes `route` as the
integer `route_id` the endpoint and slow-requests tools return, or as a string.

## Operations — regression detection

`RailsPulse::Operations` is the interface anything built on top of Rails Pulse (dashboards,
findings, agent tooling) should use to answer "did this get worse?" and "when did it change?".
It reads only from summaries, so it stays available long after raw requests have aged out of
retention.

- **`Operations::Compare`** — measures a subject's recent behaviour against its own history.
  - `Compare.call(subject, metric: :p95, as_of: Time.current)` → a `Comparison`, always
    returned; ask it `comparable?` before reading a verdict. `subject` is a `Route`, `Query`,
    `Job`, or `:requests`. `metric` is `:p50`, `:p95`, `:p99`, `:avg`, or `:error_rate`.
  - `Compare.scan(scope, metric: :p95, as_of: Time.current)` → an `Array<Comparison>` for
    every record in `scope` (a `Route`, `Query`, or `Job` relation or class), filtered to
    comparisons with usable data on both sides.
- **`Operations::Comparison`** — the value object `Compare` returns. Read-only; carries
  `subject`, `metric`, `period_type`, `baseline_value`, `baseline_count`, `baseline_periods`,
  `current_value`, `current_count`, plus derived `comparable?`, `delta`, `ratio`,
  `percent_change`, `direction` (`:up`/`:down`/`:flat`/`:unknown`), and `unit`.
- **`Operations::ChangePoint`** — estimates when a metric changed by finding the split in a
  time series that best separates a "before" from an "after". Precision is bounded by how long
  hourly summaries are retained (`config.hourly_summary_retention`); beyond that window the
  estimate is pinned to a day, and the result says which.
  - Returns a `ChangePoint::Result` struct: `at`, `granularity` (`"hour"` or `"day"`),
    `before_value`, `after_value`, `before_count`, `after_count`, plus `ratio`, `delta`, and
    `hourly?`.

`Operations::Metric`, `Operations::Series`, and `Operations::Subject` are internal helpers used
by `Compare` and are not part of this contract.

> The `Operations` namespace visually collides with the `Operation` model and
> `OperationsController` (the per-request timeline). The name is being kept for 1.0; a rename
> would be a breaking change and is not currently planned.

## Background jobs

Each is an `ActiveJob`; enqueue it the same way as any other job in the host app.

- `RailsPulse::SummaryJob.perform_later(target_hour = nil)` — rolls up hourly, and (at
  hour/day/week/month boundaries) daily, weekly, and monthly summaries ending at
  `target_hour` (default: the start of the hour one hour ago).
- `RailsPulse::CleanupJob.perform_later` — runs retention-based cleanup when
  `config.archiving_enabled`; returns the stats hash from `CleanupService`, or `nil` if
  archiving is disabled.
- `RailsPulse::BackfillSummariesJob.perform_later(start_date, end_date, period_types = ["hour", "day"])`
  — backfills summaries for an existing date range.

## Rake tasks

| Task | Purpose |
|---|---|
| `rails_pulse:status` | Reports schema, migration, route-backfill, and initializer state; exits 1 when something needs action. |
| `rails_pulse:migrate_routes` | Backfills controller actions, normalizes paths, and consolidates multi-verb routes on existing route rows. |
| `rails_pulse:record_deployment[revision]` | Records a deployment event. |
| `rails_pulse:finish_deployment[revision]` | Marks the latest deployment for a revision as finished. |
| `rails_pulse:backfill_summaries` | Backfills summary data from existing requests and operations. |
| `rails_pulse:cleanup` | Performs data cleanup based on configured retention policies. |
| `rails_pulse:cleanup_stats` | Shows current table sizes and cleanup configuration, without deleting anything. |
| `rails_pulse:install_assets` | Copies pre-built dashboard assets into `public/assets` without running the host's JS compressor. |

`rails_pulse:install`, `install_migrations`, and `install_config` exist to support the
generators below and are not typically invoked directly.

## Generators

- `rails generate rails_pulse:install` — sets up a new installation: schema, initializer,
  migrations.
- `rails generate rails_pulse:upgrade` — brings an existing installation's schema and
  initializer up to date with the running gem version.

## Tracker

`RailsPulse::Tracker` is the async writer; only these two entry points are public:

- `RailsPulse::Tracker.stats` — `{ queue_size:, dropped:, running: }` for the background
  writer thread. Zeros before the writer has been used.
- `RailsPulse::Tracker.flush!` — persists everything currently queued and stops the writer.
  The next tracked request starts it again. Intended for tests and shutdown hooks.

## Schema drift guard

`RailsPulse::SchemaCheck` answers whether the live database matches what the running gem
version expects, pausing tracking (and returning a 503 from the dashboard) when it does not.

- `SchemaCheck.current?` — `true` when every required table and sentinel column is present.
- `SchemaCheck.missing` — a hash of table → missing columns (or `[:table]` for a table that
  doesn't exist at all); empty when current or when the check is disabled.

`config.schema_check_enabled = false` turns the guard off entirely.

## What is not covered

Everything else — including but not limited to `RailsPulse::Cards::*`, `Charts::*`,
`Tables::*`, all controllers and views, `TimeRangeConcern` and friends, `RequestCollector`,
`OperationSubscriber`, and any method on the classes above not listed here — is internal
implementation detail. It may change shape, move, or be removed in a minor release. This
includes the CLI and MCP server's internals (`RailsPulse::CLI::Client`, `Formatter`, and each
per-resource command/tool class) — only the commands and tools named above, and the JSON API
endpoints they call, are the contract.
