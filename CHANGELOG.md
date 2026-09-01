# Changelog

All notable changes to Rails Pulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- **Exception messages are now actually redacted.** The 0.4.0 sanitizer ran
  `ActiveSupport::ParameterFilter` in a way that only fired when the host
  filtered a key literally named `message`, so `password=…`, `token: …`, and
  MySQL `Duplicate entry '<value>'` messages were stored verbatim. Messages now
  have `key=value` / `key: value` / `"key":"value"` fragments masked whenever the
  key matches `config.filter_parameters` (same rules as logged params), MySQL
  duplicate-entry values are redacted alongside the existing PostgreSQL
  `DETAIL:` clause, and job-run failure messages (`rails_pulse_job_runs.error_message`)
  go through the same sanitizer instead of being stored raw and unbounded.
- **CSRF protection is now declared by the engine.** `RailsPulse::ApplicationController`
  calls `protect_from_forgery with: :exception` itself instead of inheriting it from the
  host's `default_protect_from_forgery`, which only `load_defaults 5.2+` enables. Hosts
  on an older `load_defaults` had no CSRF protection on any engine endpoint (tags,
  exception status, query reanalyze, session filters). Brakeman's `CheckForgerySetting`
  is no longer skipped.
- **Authentication hooks fail closed.** An `authentication_method` that returned
  `false` without rendering or redirecting used to grant access — `proc { current_user&.admin? }`
  looked right and let every non-admin in. Literal `false` is now a 403; `nil`
  (what the documented `unless … redirect_to … end` style returns on success) still allows.
- **EXPLAIN hardening.** The query analyzer now refuses SQL containing `;`, `--` or `/*`
  anywhere (PostgreSQL's `execute` runs every statement in a string, so a captured
  `SELECT …; UPDATE …` would have re-run the UPDATE on each page view), runs the
  PostgreSQL EXPLAIN inside `SET LOCAL transaction_read_only = on` with a 5s
  `statement_timeout` instead of `Timeout.timeout`, and always rolls its savepoint back.
- **Deployments API input is bounded.** `revision` is capped at 255 characters,
  serialized `metadata` at 4 KB, and `started_at` may be at most one hour in the future
  (a forged future marker would have stamped every later exception with a revision
  that never shipped). `rails_pulse_deployments` now has a count cap
  (`max_table_records`, default 1 000) enforced by `CleanupService`; deployments are
  never pruned by age.
- **Backtrace source snippets are limited to `app/`, `lib/` and `config/routes.rb`**
  (`.rb`, `.erb`, `.rake`, `.haml`, `.slim`, `.jbuilder`). Previously any file under
  `Rails.root` was readable through a backtrace frame, including initializers with
  inline keys, `config/database.yml`, and `.env`.
- **Standalone dashboard session cookie is `Secure` in production** (override with
  `RAILS_PULSE_INSECURE_SESSION=1`). The rackup's "no Rails app" branch, which could
  never boot (`NameError: uninitialized constant Rails`), is replaced with a clear
  error; the deployment docs now give the working invocation.

### Added

- **`exception_message_filter` config option** — an optional `->(message, exception)`
  hook applied after the built-in redaction for app-specific patterns. If the hook
  raises, the message is stored as `[FILTERED]` rather than unfiltered.
- **`authorize` config option** — a fail-closed predicate, `->(controller) { … }`
  (or a zero-argument proc run in the controller). Anything falsy is a 403. Runs after
  `authentication_method` when both are set, and replaces the HTTP Basic fallback on
  its own. This is now the recommended way to gate the dashboard.

### Fixed

- **Tag filters work on SQLite for tags containing `_`.** The `LIKE` patterns were
  escaped but issued without an `ESCAPE` clause; SQLite has no default escape
  character, so `my_tag` never matched and "hide records tagged my_tag" hid nothing.
  All three adapters now get an explicit `ESCAPE '!'`.
- **Hand-edited query strings no longer 500.** `?q=string`, unparseable custom date
  ranges, unparseable `occurred_at` filters, a non-array `enabled_tags`, and
  oversized or unparseable session time filters all fall back to defaults instead of
  raising. Session-stored presets and performance thresholds are validated against
  the known values.

## [0.4.0.pre.1] - 2026-08-29

This release contains a **breaking schema change** and requires a one-time data
migration. Read "Upgrading from 0.3.x" below before deploying. Take a database
backup first: the route migration is irreversible.

### Removed

- **BREAKING — `rails_pulse_routes.method` is dropped.** The HTTP verb now lives on
  each request (`rails_pulse_requests.method`); a route carries an `http_methods`
  array instead. All application, worker, and dashboard processes must be restarted
  together against the migrated schema. A rolling restart that leaves 0.3.x
  processes running will silently drop request tracking and 500 the routes dashboard.
- **BREAKING — the route migration is irreversible.** `db:rollback` raises
  `ActiveRecord::IrreversibleMigration` on
  `ChangeRailsPulseRoutesToMultiVerbModel`, and routes merged by
  `rails_pulse:migrate_routes` are deleted with no audit trail. Recovery from a bad
  upgrade is restore-from-backup only.

### Changed

- **BREAKING — route identity is now `[controller_action, path]`.** GET `/users`
  (`users#index`) and POST `/users` (`users#create`) are distinct routes. Dynamic
  paths are normalized at capture time (`/posts/42` → `/posts/:id`).
- **A one-time backfill is mandatory.** `rails rails_pulse:migrate_routes` backfills
  `controller_action` (from the live router, then from request history), collapses
  historical literal paths, and merges routes sharing an action (GET+POST `/sign_in`
  → `sessions#new`). A schema migrate alone leaves the Action column empty. The
  upgrade generator and the dashboard both warn when the step is outstanding.

### Added

- **Exception tracking** — Captures unhandled exceptions from web requests and
  background jobs, groups them by class and location, and displays backtraces (first
  50 frames) with filtered request params in a new Exceptions tab. **Exception
  messages are stored unfiltered** and can contain literal data — a
  `PG::UniqueViolation` message, for example, embeds the conflicting value.
- **`track_exceptions` config option** — Gem default is `false`, so existing installs
  do not begin capturing on upgrade; the upgrade generator inserts `false`
  explicitly. The install template sets `true` for new apps.
- **`capture_exception_params` config option** — Captures request params alongside
  each occurrence, filtered via Rails' `filter_parameters`. Occurrences whose params
  exceed 10 KB after filtering are stored without params. Default `true`, and only
  consulted while `track_exceptions` is on.
- **Upgrade generator syncs new initializer settings** — Appends keys (and
  `max_table_records` entries) the host file does not already mention, without
  rewriting existing values. Review with `git diff`.

### Fixed

- Fixed upgrading when using a separate database installation.
- Separate-database installs set `schema_dump: false`, so `db:migrate` no longer
  dumps or loads `db/rails_pulse_structure.sql` (#189).
- Fixed `assets:precompile` failing on memory-constrained hosts by not registering
  dashboard assets with the host Sprockets pipeline. Precompile copies the pre-built
  files into `public/assets` (digested, no compressor) so `config.asset_host` and
  CDN-only CSP work; development and hosts without a pipeline still use
  `/rails-pulse-assets/<gem-version>/...`.
- SQLite `schema.rb` now keeps the partial unique index on unrecognised routes
  (`WHERE controller_action IS NULL`). A raw `CREATE INDEX` was dumped without the
  predicate, so `db:schema:load` and parallel tests unique-constrained every path.

### Upgrading from 0.3.x

Applies to every 0.3.x release (0.3.0 through 0.3.3). **Back up your database first.**

```bash
bundle update rails_pulse
rails generate rails_pulse:upgrade
rails db:migrate                  # separate Pulse database: rails db:migrate:rails_pulse
rails rails_pulse:migrate_routes  # required — schema migrate alone leaves Action empty
```

Then restart **all** processes together, not as a rolling deploy.

Separate-database hosts: add `schema_dump: false` to the `rails_pulse` entry in
`config/database.yml` and delete `db/rails_pulse_structure.sql` if it exists. Do not
run `db:setup` / `db:prepare` as a substitute for `db:migrate:rails_pulse`.

Exception tracking stays off after upgrading. Set `config.track_exceptions = true`
once you have reviewed what is captured.

## [0.3.3] - 2026-06-23

- **Deployment tracking** — Record deployments via `POST /rails_pulse/deployments` or `rake rails_pulse:record_deployment[sha]`. Deployments appear as vertical marker lines on performance charts so you can correlate releases with regressions
- **`deployment_api_token` config option** — Secures the deployments endpoint with a token header for CI/CD use
- All multi-series charts now use a native ECharts time axis (`[timestamp_ms, value]` pairs) instead of a separate labels array, enabling deployment markers and better zoom behaviour

## [0.3.0] - 2026-04-30

This is the largest release to date — a full UI overhaul across every section of
the dashboard. Charts are now switchable, the dashboard surfaces health status
automatically, and the underlying controller and model code has been substantially
refactored. Existing installs need to run the two new migrations. Hopefully future
releases will be smaller and more incremental than this one.

### Added

- **New chart types across all sections** — Routes, queries, and jobs now have dedicated chart panels with switchable chart types (response time percentiles, request volume, error rate, execution volume, duration, failure rate)
- **Dashboard health summary** — New `HealthSummary` model surfaces an overall health status and highlights routes/queries/jobs that need attention
- **Dashboard "Needs Attention" section** — Automatically surfaces slow routes, high error rates, and problematic jobs without manual digging
- **Storage pressure indicator** — Tracks and displays database storage growth so you know when to adjust retention settings
- **Flame graph view for requests** — Request detail pages now include a flame graph visualisation of operation timing
- **P95 duration tracking for jobs** — Job runs now record and display p95 duration alongside average duration
- **Database load metric for queries** — New card and chart tracking cumulative database load (execution count × avg duration) over time
- **Diagnostic fields for queries** — Query show pages now surface diagnostic information alongside existing analysis
- **Chart series toggle** — Show/hide individual series on charts without leaving the page
- **Performance status concern** — Shared `HasPerformanceStatus` concern for models that report a health status
- **Metric strip component** — New compact summary strip component for displaying multiple metrics inline
- **Setup banner** — Onboarding banner shown to users who haven't completed setup
- **Time range selector** — Redesigned time range UI with a custom date range option
- **Suggestions service** — Query show pages surface optimisation suggestions (caching, controller, SQL, HTTP, view) via dedicated suggestion services
- **Statistics module** — New `RailsPulse::Statistics` module for shared statistical calculations
- **Cleanup stats reporter** — Detailed reporting on what the cleanup job removed each run
- **Cleanup task runner** — Extracted cleanup orchestration into `CleanupTaskRunner` for testability
- **Config and migration installers** — Extracted install/upgrade logic into `ConfigInstaller` and `MigrationInstaller` classes
- **Schema parser** — New `SchemaParser` for reading and diffing schema state during upgrades
- **Icon helper** — Centralised `IconHelper` for rendering SVG icons
- **Route helper** — Centralised `RouteHelper` for building internal dashboard links
- **CSP helper** — Dedicated `CspHelper` for content security policy nonce management
- **Backfill summaries job** — New job to backfill summary records for historical data

### Changed

- **Dashboard redesigned** — Full dashboard overhaul with health summary, attention sections, and chart panels replacing the previous card layout
- **Routes, queries, and jobs index pages redesigned** — Consistent layout with metric cards, switchable chart tabs, and paginated tables
- **Metric card component updated** — Cards now support a richer data structure with trend indicators
- **Application controller refactored** — Controller concerns split into focused modules (`ChartTableConcern`, `MetricCardConcern`, `PaginationConcern`, `SessionFiltersConcern`, `TagFilterConcern`, `TimeRangeConcern`, `ZoomRangeConcern`)
- **`normalized_sql` column expanded to `text`** — Removes the 1000-character limit on PostgreSQL and MySQL (migration provided for existing installs)
- **Diagnostic fields added to queries table** — New columns captured at instrumentation time
- **Summary job and service refactored** — Cleaner separation between job scheduling and summary calculation logic
- **Cleanup job refactored** — Now uses `CleanupTaskRunner` and reports statistics via `CleanupStatsReporter`
- **Configuration expanded** — New configuration options exposed in the initializer template
- **Upgrade generator simplified** — Generator now delegates to `MigrationInstaller` and `ConfigInstaller`
- **Asset server middleware updated** — Improved asset serving reliability
- **Request collector middleware updated** — Performance improvements and cleaner instrumentation
- **Operation subscriber refactored** — Cleaner event handling and reduced complexity
- **Seeds refactored** — Dummy app seeds split into focused files under `db/seeds/rails_pulse/`
- **Test coverage significantly expanded** — Controller concerns, helpers, models, services, and system tests all substantially extended

### Removed

- `StatusHelper` removed — status rendering consolidated into model concerns and view components
- `ChartFormatters` helper removed — chart formatting moved into chart model classes
- `chart_formatters_test.rb` removed alongside the helper
- Slow queries and slow routes table models removed — replaced by the Needs Attention system
- Unused `average_response_time` and `p95_response_time` dashboard chart classes removed
- `requests/tables/index.rb` and related test removed — requests index now uses a shared approach
- `routes/cards/average_response_times` and `routes/charts/average_response_times` removed — replaced by percentile-based equivalents
- `jobs/cards/average_duration` and `jobs/cards/total_jobs` removed — replaced by updated cards
- Timezone controller removed
- Application mailer stub removed

## [0.2.7] - 2026-04-17

No changelog entry — see git history.

## [0.2.6] - 2026-04-15

No changelog entry — see git history.

## [0.2.5] - 2026-04-14

No changelog entry — see git history.

[Unreleased]: https://github.com/railspulse/rails_pulse/compare/v0.4.0.pre.1...HEAD
[0.4.0.pre.1]: https://github.com/railspulse/rails_pulse/compare/v0.3.3...v0.4.0.pre.1
[0.3.3]: https://github.com/railspulse/rails_pulse/compare/v0.3.2...v0.3.3
[0.3.0]: https://github.com/railspulse/rails_pulse/compare/v0.2.7...v0.3.0
[0.2.7]: https://github.com/railspulse/rails_pulse/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/railspulse/rails_pulse/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/railspulse/rails_pulse/releases/tag/v0.2.5
