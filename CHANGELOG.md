# Changelog

All notable changes to Rails Pulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Fixed upgrading when using separate database installation

## [0.3.3] - 2026-06-23

- **Exception tracking** — Captures unhandled exceptions from web requests and background jobs, groups them by class and location, and displays full backtraces with filtered request params in a new Exceptions tab
- **`track_exceptions` config option** — Enable or disable exception tracking (default: `true`)
- **`capture_exception_params` config option** — Capture request params alongside each exception occurrence. Params are filtered via Rails' `filter_parameters` config; occurrences with params larger than 10KB after filtering are stored without params. Set to `false` for strict data-minimisation requirements (default: `true`)
- **Deployment tracking** — Record deployments via `POST /rails_pulse/deployments` or `rake rails_pulse:record_deployment[sha]`. Deployments appear as vertical marker lines on performance charts so you can correlate releases with regressions
- **`deployment_api_token` config option** — Secures the deployments endpoint with a token header for CI/CD use
- All multi-series charts now use a native ECharts time axis (`[timestamp_ms, value]` pairs) instead of a separate labels array, enabling deployment markers and better zoom behaviour

## [0.3.0] - 2026-04-19

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

## [0.2.7] - 2026-04-19

No changelog entry — see git history.

## [0.2.6] - 2026-04-18

No changelog entry — see git history.

## [0.2.5] - 2026-03-xx

No changelog entry — see git history.

[Unreleased]: https://github.com/railspulse/rails_pulse/compare/v0.3.0.pre.1...HEAD
[0.3.0.pre.1]: https://github.com/railspulse/rails_pulse/compare/v0.2.7...v0.3.0.pre.1
[0.2.7]: https://github.com/railspulse/rails_pulse/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/railspulse/rails_pulse/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/railspulse/rails_pulse/releases/tag/v0.2.5
