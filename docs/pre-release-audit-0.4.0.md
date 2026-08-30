# Rails Pulse 0.4.0.pre.1 — Pre-Release Audit

Audit date: 2026-08-29 · Branch `v0.4.0.pre.1` at `519d5bd` · Ruby 3.3.6 / Rails 8.1.3

**Verdict: do not publish yet.** The test suite is green (3068 runs, 8381 assertions, 0
failures, 0 errors, 1 skip) and the migrations themselves are carefully written and
idempotent. But there are **9 blockers**, and — critically — the two most dangerous are
*not* in the migrations. They are in the surrounding machinery: a rake helper that marks
migrations applied without running them, and a gem-shipped initializer that overrides
host configuration.

The recurring theme across every slice is the same, and it is the direct mechanical cause
of "migration paths have broken for existing users in the past":

> **The code that protects upgrades is not the code that CI runs.**
> `rake test` omits `test/migrations`. `test/upgrade_matrix/` is empty and referenced
> nowhere. No CI job configures `config.connects_to`. `bin/test_generators` runs in no
> workflow. The separate-DB upgrade check is a 7-step manual checklist in
> `docs/releasing.md`. Coverage thresholds are never evaluated.

Fixing §1–§9 makes the release safe. Fixing §22 is what stops the next one breaking.

### Scope

Six parallel audits: migrations/upgrade paths, security, runtime/setup matrix, packaging/CI,
in-repo docs, and the website repo (`/Users/scott/studioomni/rails_pulse_website`). Every
finding below is grounded in a `path:line` reference. Claims marked `[INFERENCE]` were
reasoned from documented behaviour but not executed.

### Upgrade safety matrix — 0.3.x → 0.4.0

| Layout | Adapter | Verdict | What breaks first |
|---|---|---|---|
| single | sqlite | Unsafe (fixable) | §3 generator overwrite prompt; then §2 uncapped exception tables |
| single | postgresql | **Unsafe** | §1 — a dashboard page view can re-run a captured production `DELETE` |
| single | mysql | Unsafe | §3, plus §12 MySQL functional index unverified; MariaDB fails outright (§13) |
| separate | sqlite | **Unsafe** | §4 — migrations marked applied without running; unrecoverable without manual SQL |
| separate | postgresql | **Unsafe** | §4, then §1 |
| separate | mysql | **Unsafe** | §4, §12, §13 |

No combination is currently safe end-to-end. Single-DB SQLite is closest.

---

## Already fixed in this pass

Applied as authorized (mechanical only) in commit `0083360`. Everything else below is a
recommendation. Line references below are post-edit; the findings sections reference
pre-edit lines that may have shifted in these four files.

| Change | File |
|---|---|
| Stopped publishing 24 MB of gitignored stale source maps, dead `vendor/assets/`, dev-only `Rakefile`/brakeman configs; added `CHANGELOG.md` | `rails_pulse.gemspec:33-39` |
| `post_install_message` now version-agnostic ("any 0.3.x"), adds backup warning, restart-together warning, separate-DB steps, and a new-install branch | `rails_pulse.gemspec:44-61` |
| `required_ruby_version` `>= 3.0.0` → `>= 3.1.0` (the true floor; see §14) | `rails_pulse.gemspec:17` |
| Added `bug_tracker_uri` and `rubygems_mfa_required` | `rails_pulse.gemspec:26-27` |
| Lockfile list now derived from `gemfiles/*.gemfile` instead of a hardcoded pair that omitted 8.1; also updates `test/dummy/Gemfile.lock` | `bin/bump_version:83-114` |
| Cut `[Unreleased]` → `[0.4.0.pre.1]`, added `### Removed` / `### Changed` for the breaking change, seeded `_Nothing yet._` so the CI gate keeps passing, fixed the dangling `[0.3.0]` link ref, corrected four wrong release dates from tags | `CHANGELOG.md` |
| Replaced transient this-release notes with evergreen asset guidance; corrected lockfile list; replaced released-version examples with `X.Y.Z` | `docs/releasing.md` |

**Result:** gem 7.4 MB → **2.5 MB**; uncompressed payload 32.10 MB → **8.22 MB**. All 12
migrations and 6 pre-built assets verified still present. Rubocop clean, `rake build` OK.

**Deliberately not bumped:** `lib/rails_pulse/version.rb` is still `0.3.3`. Run
`bin/bump_version 0.4.0.pre.1` (now fixed) so version and all lockfiles move together.

---

# BLOCKERS

## §1 — `EXPLAIN (ANALYZE, BUFFERS)` re-executes captured production writes

**Severity: CRITICAL** · PostgreSQL + shared database (the default) · New in 0.4.0

The single most serious finding. Opening a query detail page can **re-run a production
`DELETE`**.

- `app/services/rails_pulse/analysis/explain_plan_analyzer.rb:190` runs
  `EXPLAIN (ANALYZE, BUFFERS) #{sql}`. On PostgreSQL, `ANALYZE` **executes** the statement.
- `:11` prefers `actual_sql` — the verbatim captured statement, new in 0.4.0 — over
  placeholder-bearing `normalized_sql`.
- `:185-188` `sanitize_sql_for_explain` strips only trailing semicolons. **No verb check
  exists anywhere in the analyzer** (verified by grep).
- `lib/rails_pulse/subscribers/operation_subscriber.rb:88-92` skips only
  `rails_pulse_`-prefixed SQL, so host-table `DELETE`/`UPDATE`/`INSERT` are captured as
  `Query` records with detail pages.
- Trigger: `GET /rails_pulse/queries/:id` → `queries_controller.rb:19` →
  `query.rb:100-106` `ensure_analyzed!` → analyzer. `POST /queries/:id/reanalyze`
  (`queries_controller.rb:22-25`) makes it repeatable on demand.

**Why 0.4.0 specifically:** before this release the analyzer only ever saw normalized SQL
with `?`/`$1` placeholders, so `EXPLAIN` errored harmlessly. `actual_sql` removed that
accidental protection. Statements from `delete_all`, `update_all`, `insert_all`, raw
`execute`, or any adapter with `prepared_statements: false` (mysql2 default; the standard
PgBouncer transaction-pooling config for PG) carry inline literals and EXPLAIN-ANALYZE
cleanly — so they run for real.

**Why it was never caught:** `:26` `return nil if Rails.env.test?` means no test reaches
this path, *and* the three Brakeman warnings for these lines are suppressed in
`config/brakeman.ignore` with the note *"EXPLAIN is read-only"* — which is false for the
PostgreSQL variant actually used.

Separate-DB installs are accidentally safe (host tables absent → EXPLAIN errors, swallowed
at `:42-45`). MySQL `EXPLAIN` and SQLite `EXPLAIN QUERY PLAN` do not execute.

**Fix:** (1) drop `ANALYZE, BUFFERS` — plain `EXPLAIN` is planner-only; if timing is wanted,
gate it behind opt-in and wrap in `BEGIN; … ROLLBACK;`. (2) Independently, anchor-match the
statement verb and refuse anything that is not `SELECT`/`WITH`. (3) Remove the three
`explain_plan_analyzer` entries from `config/brakeman.ignore` and re-triage. (4) Replace the
`Rails.env.test?` bail-out with a seam so the path becomes testable.

## §2 — The gem ships a live `RailsPulse.configure` block into every host app

**Severity: BLOCKER** · All setups

`config/initializers/rails_pulse.rb` in the gem root is a real, 12,887-byte
`RailsPulse.configure do |config| … end` block. `Rails::Engine`'s
`initializer :load_config_initializers` loads it in **every host application**, and
`rails_pulse.gemspec` globs `config/**/*`, so it ships.

At `config/initializers/rails_pulse.rb:283-288` it sets `max_table_records` to a **four-key**
hash — `requests`, `operations`, `routes`, `queries`. Missing:
`rails_pulse_exception_occurrences`, `rails_pulse_exception_groups`, `rails_pulse_job_runs`,
`rails_pulse_jobs`. The correct eight-key defaults exist at
`lib/rails_pulse/configuration.rb:71-80` and are simply overwritten.

Count-based cleanup is key-presence-gated — `lib/rails_pulse/cleanup_service.rb:85-86`,
`:140-141`, `:164-165`, `:229-230` all `return 0 unless max_records`. So **the new exception
tables have no count cap for any user**, and `rails_pulse_job_runs` has been silently
uncapped since job tracking shipped. The project's own reference app has the same drift
(`test/dummy/config/initializers/rails_pulse.rb:277-282`) while setting
`track_exceptions = true`.

Beyond the missing keys, shipping a live configure block is itself a landmine: it silently
overrides `Configuration` defaults for settings the host never mentioned.

**Fix:** delete `config/initializers/rails_pulse.rb` from the gem — the sample config belongs
solely at `lib/generators/rails_pulse/templates/rails_pulse.rb`. Then make
`max_table_records=` **merge** into the defaults rather than replace, so users carrying an
older explicit hash still get caps on tables added later. Add the four missing keys to the
dummy app.

## §3 — Upgrade generator prompts on `db/rails_pulse_schema.rb`, and can hang in CI/Docker

**Severity: BLOCKER** · All setups

`lib/generators/rails_pulse/upgrade_generator.rb:130` is
`copy_file "db/rails_pulse_schema.rb", "db/rails_pulse_schema.rb"` — **no `force: true`**.
On every real 0.3.x host the file differs, so Thor emits `conflict … Overwrite? [Ynaqdhm]`.

- Answering `n` leaves the host schema at 0.3.3 — which, combined with §4, permanently
  poisons the test/CI database.
- In a non-TTY deploy step, Thor's `file_collision` loop has no terminating input.
  `[INFERENCE]` on the hang specifically.
- `install_generator.rb:90` calls this file "your single source of truth", i.e. it is
  gem-owned and should never be a conflict.

Never caught because `test/support/generator_test_helpers.rb:104-108` pre-seeds the
destination with the *current* schema, so `copy_file` reports "identical".

**Fix:** add `force: true`, and add a generator test that seeds a divergent 0.3.3 schema and
asserts it is rewritten.

## §4 — `record_rails_pulse_migrations_applied` marks migrations applied without running them

**Severity: BLOCKER** · Separate database, all adapters

**This is the highest-value migration finding — the exact failure mode that has burned users.**

`lib/tasks/rails_pulse.rake:62-91` inserts a `schema_migrations` row for **every** file in
`db/rails_pulse_migrate/` after any schema load. It is invoked from
`db:schema:load_rails_pulse` (`:15`), which is appended to `db:prepare` (`:26-28`),
`db:setup` (`:30-32`) and `db:test:prepare` (`:39-47`).

But the schema load is a no-op on an existing database:
- `db/rails_pulse_schema.rb:26-29` — *"If all tables exist, skip creation entirely"* →
  `return`.
- `:31` guards the routes table with `unless connection.table_exists?(:rails_pulse_routes)`,
  so an existing 0.3.3 routes table is **never altered**.

Sequence for a separate-DB host: run the upgrade generator (new files land in
`db/rails_pulse_migrate/`) → run `rails db:setup` or `db:prepare` instead of
`db:migrate:rails_pulse` → schema load does nothing → `20260610000001/2/3` are recorded as
applied. Result: routes keeps `method`, never gains `controller_action` or `http_methods`,
and **`db:migrate:rails_pulse` now reports "up to date"**. Every tracked request and the
routes dashboard raise on the missing `NOT NULL http_methods`. Recovery requires manual
`DELETE FROM schema_migrations`.

Compounding: `separate_database_setup?` (`:51-56`) returns true for **single-DB installs
too**, because `install_generator.rb:20-22` creates `db/rails_pulse_migrate/.keep` for both
modes (§17).

**Fix:** only record a version if the load actually produced that migration's effect — gate
the whole routine on the schema load having created tables, and additionally assert
`controller_action`/`http_methods` exist before recording the `20260610*` versions. Better:
have `RailsPulse::Schema` **raise** rather than silently skip when an existing table is
missing expected columns.

## §5 — `JobRunCollector` is not failure-isolated: Pulse errors corrupt host job control flow

**Severity: BLOCKER** · Any setup with `track_jobs = true`

`lib/rails_pulse/job_run_collector.rb` violates the "Pulse must never raise into the host"
invariant in three distinct ways. `lib/rails_pulse/active_job_extensions.rb:7-11` wraps every
ActiveJob `perform` in it.

1. `:20-23` — `find_or_create_job` / `create_job_run` run **before** `yield` with no rescue.
   A DB blip, unmigrated tables, or an exhausted pool means **the job body never runs** and
   the job raises `StatementInvalid`. The queue retries forever, failing identically.
2. `:31-34` — the success path `job_run.update!(status: "success", …)` has no rescue. A job
   that **already completed successfully** is recorded as failed and **re-raised**, so the
   queue retries completed work: double charges, double emails.
3. `:35-47` — if the failure-recording `update!` itself raises, that Pulse exception
   **replaces** the application's exception. The host's error reporter, `retry_on` and
   `discard_on` matchers all see the wrong class.

Additionally `ExceptionCaptureService.capture` at `:45` runs **outside**
`with_recording_suppressed`, so in modes 1–2 Pulse captures its own internal error as an
application exception, and the capture's own SQL is persisted as operations of the job run.

**Fix:** wrap each of the three write sites in its own `rescue => e; log; end` so no Pulse
failure alters control flow; ensure the `rescue` branch always re-raises the **original**
error; move the `capture` call inside `with_recording_suppressed`.

## §6 — `config.async = true` is not asynchronous — it blocks the request

**Severity: BLOCKER** · Default configuration, all setups

`lib/rails_pulse/tracker.rb:16-20` uses `Async { perform_tracking(data) }`. With no running
reactor and no `Fiber.scheduler` — i.e. every Puma/Passenger/Unicorn worker — `Kernel#Async`
constructs a reactor and **runs it to completion synchronously**.

Measured in this repo:

```
Async { sleep 0.25; order << :inside }; order << :after
→ order=[:inside, :after]   elapsed=251.3ms   VERDICT: BLOCKS
```

And `lib/rails_pulse/middleware/request_collector.rb:59` calls
`Tracker.track_request(tracking_data)` **before** returning `[status, headers, response]`.
So route find-or-create, `Request.create!`, and `Operation.insert_all!` for every operation
all complete before a single byte reaches the client.

The comment at `:58` says *"non-blocking if async mode enabled"*.
`docs/deployment-modes.md:201-212` advertises *"~0.1ms overhead per request / Database
writes happen in background fibers / Non-blocking for request processing"*. All false.
`config.async` defaults to `true` everywhere (`configuration.rb:102`), and only the dummy app
disables it.

There is also no failure boundary: because the reactor is created inside the request, an
exception escaping `perform_tracking`'s inner rescue propagates into the middleware (§8).

**Fix:** pick one and be honest. Either (a) rename to `config.defer_writes` and document
that writes are inline, or (b) make it genuinely off-request — a bounded in-process queue
drained by a dedicated thread with an explicit drop policy. `Async` is the wrong tool: the
DB drivers are blocking, so even a real reactor would serialise. Either way, regenerate
`bin/benchmark` numbers and `docs/deployment-modes.md:201-212`.

## §7 — Deployments endpoint fails open to anonymous writes

**Severity: BLOCKER** · Any environment where `Rails.env != "production"`

`app/controllers/rails_pulse/deployments_controller.rb:44-52` enforces the token only when
`deployment_api_token.present?`. Otherwise it delegates to `authenticate_rails_pulse_user!`,
whose first line (`application_controller.rb:84`) is
`return unless RailsPulse.configuration.authentication_enabled`.

`authentication_enabled` defaults to `Rails.env.production?`
(`configuration.rb:82`). A `before_action` that returns without rendering **does not halt the
chain**. So on `staging`, `qa`, `review`, `demo`, or any per-PR preview app, anyone who can
reach the mount can POST unlimited deployment rows.

Not merely cosmetic:
- `deployment.rb:5-6` validates only presence — no length limit — and `metadata: {}` permits
  an arbitrary nested hash serialised to JSON. One request can insert megabytes.
- No rate limiting.
- `rails_pulse_deployments` is **absent from `max_table_records`** and has **no time-based
  cleanup** (grep for `Deployment` in `cleanup_service.rb` → nothing). Rows are permanent.
- `exception_capture_service.rb:29-31` stamps every exception with the latest deployment
  revision, so one forged row with a future `started_at` poisons `deploy_sha` on all
  subsequent exception records.

**Fix:** fail closed — when no token is configured *and* `authentication_enabled` is false,
return 401. Cap `revision` length and serialised `metadata` bytes. Add
`rails_pulse_deployments` to `max_table_records` and to `CleanupService`.

## §8 — Deploying 0.4.0 code before migrations: separate-DB hosts 500 on every request

**Severity: BLOCKER** · Separate DB before `db:prepare`; degraded elsewhere

Extremely common on Kamal/Heroku, where code ships before the release task completes.

- **Single DB:** the host **stays up**. `Route.find_or_create_for_request` →
  `find_by(controller_action:, path:)` (`route.rb:34`) raises `StatementInvalid`, caught by
  `tracker.rb:55-57`. But **every request logs an error** (log flood at request volume) and
  zero rows are written for the whole window. The dashboard **500s** — any routes/requests
  page selects `http_methods` (`route.rb:13`, `:56-61`, `:128`).
- **Separate DB:** `ApplicationRecord.connection_pool.with_connection` at `tracker.rb:33` is
  **outside** the rescue. If the Pulse database does not exist yet, the checkout raises
  `NoDatabaseError`, which propagates through `perform_tracking` → `track_request` →
  `RequestCollector#call`, which has **no rescue anywhere**
  (`request_collector.rb:8-66`). **Result: 500 on every host request.** Async mode does not
  help (§6).
- **`track_jobs = true`:** all background work fails via §5.

Good news: boot is clean (no engine initializer touches the DB), the upgrade banner is
column-guarded (`route.rb:74-75`), and cleanup guards the new tables
(`cleanup_service.rb:200-204`).

**Fix:** move the `with_connection` call inside the rescue in `tracker.rb`, and wrap
`RequestCollector#call`'s tracking invocation in a rescue of its own. Pulse must never be
able to 500 a host request.

## §9 — Website publishes upgrade instructions that break 0.3.x → 0.4.0

**Severity: BLOCKER** · Documentation

`https://railspulse.com/documentation/installation` (the gemspec `documentation_uri`) **does
resolve** — verified live, via a meta-refresh stub to `/documentation/v0-3/installation`. It
does not 404. It serves 0.3-era content and will keep doing so after 0.4.0 ships.

Worse, `src/content/docs/v0-3/faq.mdx:80-88` publishes:

> *"How do I update Rails Pulse? 1. Update the version in your Gemfile 2. Run
> `bundle update rails_pulse` 3. Run `rails db:migrate` 4. Restart your Rails server"*

This omits `rails generate rails_pulse:upgrade` — **without which no migrations are copied at
all, so `db:migrate` is a no-op** — and omits `rails_pulse:migrate_routes`. For separate-DB
hosts `db:migrate` is also the wrong task. There is no upgrade page at all
(`src/constants/sidebar.ts:3-38`), and `rails_pulse:upgrade` appears only in
`troubleshooting.mdx:50-56` under "Missing Columns After Gem Update".

Also blocking:
- **Zero 0.4.0 content.** Grep for `exception|track_exceptions|capture_exception_params`
  across `src/content/docs/` → **no matches**. Same for
  `controller_action|http_methods|migrate_routes`.
- **`schema_dump: false` appears in none of the eight `database.yml` examples**
  (`database.mdx:73-77,87-95,103-111`; `databases.mdx:49-58,75-84`;
  `separate-dashboard.mdx:72-76`; `troubleshooting.mdx:320-323,344-348`). Users building
  config from the website hit the exact `relation already exists` failure of issue #189.
- **Two configured redirects dead-end in 404s** (verified live): `astro.config.mjs:22`
  points `/documentation/standalone` at a page that does not exist (the file is
  `standalone-dashboard.mdx`); `:24` points `/documentation/testing` at nothing.
  `https://railspulse.com/documentation` is itself a **404** — no index page.

**Fix — ordered:**
1. Add `astro check` + a link checker to `package.json` and `deploy.yml` **first**; every
   subsequent step is a mass link edit and nothing currently validates them.
2. **Collapse to unversioned docs.** Recommended over forking a `v0-4` tree: findings
   §19–§21 are drift that already accumulated inside *one* tree, and a second doubles the
   surface. `git mv src/content/docs/v0-3/* src/content/docs/`, strip `/v0-3` from the 12
   in-content links and `DocsHeader.astro:38`, delete `src/constants/versions.ts` and
   `VersionSwitcher.astro`.
3. **Invert the redirect table** so `/documentation/v0-3/<page>` → `/documentation/<page>`,
   preserving inbound links from already-published 0.3.x gemspecs. Fix `standalone`, drop
   `testing`, add a `/documentation` index.
4. **Write `upgrade.mdx`** — port `CHANGELOG.md` `[0.4.0.pre.1]` and
   `docs/database_setup.md:66-119`, split single-DB vs separate-DB, with explicit callouts
   for the dropped column, restart-together, `schema_dump: false`, irreversibility, and the
   mandatory backfill. Then **rewrite `faq.mdx:80-88`** to link to it.
5. Add `schema_dump: false` to all eight YAML examples.
6. **Write `exceptions.mdx`** covering what is captured, the 50-frame cap, the Exceptions
   tab, `track_exceptions` defaults, the 10 KB params cap, and that **messages are stored
   unfiltered**.

---

# HIGH

## §10 — Unfiltered exception messages leak literal PII

`exception_capture_service.rb:118` and `:200` store
`@exception.message.to_s.truncate(500)` with **no filtering**, into both the group and every
occurrence. Unlike params there is no opt-out switch — the only lever is disabling exception
tracking entirely.

Highest-frequency vectors:
- `ActiveRecord::StatementInvalid` / `PG::UniqueViolation` — the message carries the driver
  error **plus the offending statement**: `duplicate key value violates unique constraint
  "index_users_on_email" DETAIL: Key (email)=(alice@example.com) already exists. : INSERT
  INTO "users" …`. Unique-violation-on-signup is among the most common production
  exceptions, and it deposits a user's email into a table with different access control from
  `users`.
- `JSON::ParserError` / `ArgumentError` quote the offending input — for a webhook, the
  request body including secrets.
- Third-party client errors (`Stripe::*`, `Faraday`) embed request URLs and query-string keys.

Aggravating: 500-char truncation is character-based, so the `DETAIL: Key (…)=(…)` clause
survives; and `preserve: true` groups are exempt from all cleanup
(`cleanup_service.rb:221-223`), so a leaked message persists indefinitely.

**Verified correct, for the record:** params genuinely *are* filtered — twice, since
`process_action.action_controller` already supplies `request.filtered_parameters` and
`filtered_params` applies `ActiveSupport::ParameterFilter` again (`:184-193`). `request_url`
uses `request.filtered_path`. The 10 KB cap exists and drops params wholesale rather than
truncating mid-JSON. Backtraces are capped at 50 frames. Those CHANGELOG claims hold.

**Fix:** run the message through `ActiveSupport::ParameterFilter` in `key=value` mode, or at
minimum strip the SQL tail from `StatementInvalid` and redact `DETAIL: Key (…)=(…)`. Add a
`capture_exception_messages` option or an `exception_message_filter` proc.

## §11 — `actual_sql` persists raw unparameterized SQL with no opt-out, cap, or docs

The schema's own comment (`templates/db/rails_pulse_schema.rb:143`) says
*"comment-stripped, **unparameterized, unbounded**"*. Populated from `payload[:sql]` with
only comment stripping (`operation_subscriber.rb:22-26`), stored verbatim, and rendered at
`operations/show.html.erb:9`.

Whether it contains real data depends on host adapter config, and for many users it does:
**mysql2 defaults `prepared_statements: false`**, so every literal is inlined —
`INSERT INTO users (email, encrypted_password) VALUES ('alice@example.com', '$2a$12$…')`
stored in plaintext and displayed. Same for PG behind PgBouncer in transaction mode. And
`update_all`/`delete_all`/`insert_all`/`execute` inline values on **all** adapters.

Not covered by `filter_parameters`. No `capture_actual_sql` toggle exists — contrast
`capture_job_arguments`, which defaults `false` precisely because arguments "may contain user
credentials, PII, API keys". No length cap. **Entirely undocumented**: no mention in
CHANGELOG, README, or the initializer template.

**Fix:** add `config.capture_actual_sql`, default `false` on upgrade and `true` only in the
new-install template (mirror the `track_exceptions` treatment); truncate to a bounded length;
document the field and the MySQL amplification.

## §12 — MySQL null-action functional index has no schema round-trip coverage

`lib/rails_pulse/route_indexes.rb:26-32` creates it with raw
`CREATE UNIQUE INDEX … ((CASE WHEN controller_action IS NULL THEN path ELSE NULL END))`
because `add_index(where:)` is silently ignored on MySQL. But
`test/lib/rails_pulse/route_indexes_test.rb:20` **skips the dump assertion on MySQL**.

`CHANGELOG.md` records that this exact bug — predicate lost in the dump, every path
unique-constrained — **already shipped once for SQLite**. The same class is now untested on
MySQL, where single-DB hosts dump `db/schema.rb` after `db:migrate`.

**Fix:** remove the `skip if mysql?`, assert the dumped index round-trips, add a
load→dump→load test, and run it in the `mysql` CI job (needs §22 first).

## §13 — MySQL functional index requires ≥ 8.0.13 and is unsupported on MariaDB

Selected purely by `adapter_name.downcase.include?("mysql")` — **MariaDB reports `Mysql2`
too**. Reached from both `db/rails_pulse_schema.rb:43` (any schema load, i.e. fresh install)
and `rails_pulse_tasks.rake:35`. On MariaDB, or MySQL < 8.0.13, this is a **syntax error**, so
installation itself fails. The gemspec declares no MySQL floor and CI pins `mysql:8.0` only.

**Fix:** declare a minimum MySQL version and raise a clear error on MariaDB, or fall back to
an application-level uniqueness strategy.

## §14 — `required_ruby_version >= 3.0.0` was unsatisfiable; Rails 7.1 has zero coverage

**Ruby 3.0: definitively unsupported**, two independent proofs:
1. **No `async` 2.x release installs on Ruby 3.0.** Queried rubygems.org: the lowest
   `required_ruby_version` across all `async` 2.x is `>= 3.1.0` (async 2.0.0). So
   `async ~> 2.0` (`gemspec:41`) made `>= 3.0.0` unsatisfiable — resolution simply fails.
2. `lib/generators/rails_pulse/upgrade_generator.rb:194` uses `Array#intersect?`, added in
   Ruby 3.1 — and it sits on the **missing-columns recovery path**, the branch that exists
   specifically to rescue broken upgrades.

No Ruby 3.2+ construct exists anywhere (`Data.define`, `ceildiv`, anonymous block
forwarding, `it`, 3.1 hash shorthand all return zero hits), so 3.1.0 is the true floor.
**Already applied** above. Decide whether to keep `>= 3.1.0` (then add a 3.1 CI cell) or
raise to `>= 3.2.0` to match what CI proves.

**Rails 7.1** is permitted by `gemspec:38` but has no Appraisal, no gemfile, and no CI cell —
and `test.yml:58-62`'s version→gemfile `case` has no `7.1` branch, so adding one to the
matrix would silently run against the root `Gemfile`. `[INFERENCE]` 7.1 probably works:
all 12 migrations declare `ActiveRecord::Migration[7.0]` and no 7.2+ API is used. But
"probably works" is the posture that breaks upgrades. Either add the cell or raise the floor
to `>= 7.2.0`.

Three different claims are currently published: gemspec `>= 7.1.0`, README badge
`Rails-7.2+`, CI 7.2/8.0/8.1. Website adds two more:
`faq.mdx:8` says **Ruby 3.3+** while `installation.mdx:10-11` says **Ruby 3.0+**.

## §15 — Unbounded route cardinality from unrecognised paths

`request_collector.rb:43-47` reads `path_parameters`; `route_path_normalizer.rb:16` is
`return @path if route_params.empty?` — **with no path params, normalisation is a
pass-through and the raw path becomes the route identity**, with `controller_action` nil.

So everything missing the Rails router lands as one row per distinct raw path: 404s from
vulnerability scanners (`/wp-login.php`, `/.env`, `/.git/config`), middleware
short-circuits, Rack apps mounted below. `ignored_routes` defaults
(`configuration.rb:338-367`) cover assets and a few health paths only.

Count cleanup cannot rescue it: `cleanup_routes_by_count`
(`cleanup_service.rb:186-191`) passes a scope of routes with **no** requests, and
`cleanup_by_count` computes `current_count` on that scope (`:88-90`). So
`max_table_records[:rails_pulse_routes] = 1000` is compared against *childless* routes only,
and any route with one request is exempt until time-based retention removes it.

**Fix:** when `controller_action` is nil and the path did not normalise, bucket it — a
sentinel (`"(unrecognized)"`) or a conservative structural normaliser (digits → `:id`, UUIDs
→ `:uuid`, 40-hex → `:sha`). Separately fix `cleanup_by_count` so `current_count` is the
table count while the delete list comes from the scope.

## §16 — Exception-group count cap is arithmetically unenforceable

`cleanup_service.rb:228-243`: `:232` `current_count = ExceptionGroup.count` (**all** groups),
`:235` `records_to_delete = current_count - max_records`, but `:236` restricts the delete
scope to `where(preserve: false).where.not(status: "ignored")`.

Once ignored + preserved groups approach the cap, it can never be satisfied — the arithmetic
asks for `total - max` deletions from a shrinking non-exempt set. And `ignored` is the
natural end state for noisy high-cardinality errors, i.e. exactly what accumulates most.
Combined with §2 (cap is `nil` anyway) and §18 (ignored groups still get upserted so never
become orphans), `rails_pulse_exception_groups` has **no working upper bound**.

**Fix:** compute overage against the deletable population — `deletable = scope.count;
return 0 if deletable <= max_records` — or delete `min(total - max, deletable)` and log when
the cap cannot be met.

## §17 — Null-action index silently skipped, and the backfill task can raise at its last step

`20260610000003_add_null_action_unique_index_to_routes.rb:5` is
`return if duplicate_null_action_paths?` — a **silent no-op** whenever two null-action rows
share a path. At `db:migrate` time that is the normal state: `20260610000002` deliberately
does not merge null-action rows, and `controller_action` is NULL for all pre-existing rows.
So any 0.3.x install with GET+POST on one path hits the early return — **and the version is
still recorded as applied**.

Two consequences:
- **Skip `migrate_routes`** → no null-action unique index ever. `find_or_insert_by_path`
  (`route.rb:45-53`) relies on it for `ON CONFLICT DO NOTHING`; without it, concurrent
  misses on the same 404 path each insert a row, permanently, splitting that path's metrics.
- **Any duplicate surviving the backfill** → `ensure_null_action_uniqueness!`
  (`rails_pulse_tasks.rake:34`) raises a bare `RecordNotUnique` as the **final** statement,
  after both backfill phases have committed. The task is documented to run against a live
  app, so any request served between consolidation and line 34 can insert a fresh duplicate.

Also: fresh installs get the index but upgraded installs may not — silent schema divergence.

**Fix:** wrap line 34 — rescue, re-run `consolidate_unrecognized_duplicates`, retry once,
then print the offending paths instead of a raw exception. Replace the migration's silent
`return` with a `say` explaining the index is deferred. Have `Route.needs_action_backfill?`
also report a missing `RouteIndexes.exists?`.

## §18 — Exception capture has no aborted-transaction recovery

`tracker.rb:63-70` has `clear_aborted_transaction` precisely because a raised request can
leave a PG connection in `PQTRANS_INERROR`. `exception_capture_service.rb:114-178` has **no
equivalent** — it calls `connection.execute` directly at `:121`/`:146`, synchronously on the
host's leased connection.

So the single most valuable exception to capture — an `ActiveRecord::StatementInvalid` — is
exactly the one that leaves the connection aborted. Capture then fails with
`PG::InFailedSqlTransaction`, is swallowed at `:65-67`, and **nothing is recorded**. The
user sees a 500 in their logs and nothing in Pulse.

Separately, because capture runs on the host's connection in single-DB setups, an exception
raised inside an app-managed `transaction do … end` that the app rescues also rolls back the
group and occurrence rows. Both effects vanish under `connects_to` — so capture reliability
differs by DB topology, undocumented.

**Fix:** extract `clear_aborted_transaction` into a shared helper and call it at the top of
`upsert_group`. Document the single-DB transaction-participation caveat.

## §19 — Dashboard unauthenticated by default outside `Rails.env.production?`

`configuration.rb:82` `@authentication_enabled = Rails.env.production?`. Every environment
not literally named `production` — `staging`, `qa`, `uat`, `demo`, preview apps — mounts a
fully open dashboard exposing SQL text, request params, and now exception backtraces. These
environments routinely carry production dumps and are routinely internet-reachable.

Production itself **fails closed correctly** (`application_controller.rb:110-120`: no
`authentication_method` → HTTP Basic → `RAILS_PULSE_PASSWORD` unset → denied, logged).
Good design.

Documentation is the weak point: `README.md:121` states plainly "no built-in
authentication", but the mount snippet 70 lines earlier (`:49-51`) is a bare
`mount RailsPulse::Engine => "/rails_pulse"` with no constraint example, and nothing
mentions the default is environment-conditional. Website `authentication.mdx` never states
the real default or the Basic-auth fallback, and `:110-111` actively recommends
`Rails.env.production?`.

**Fix:** default to `true` unless `Rails.env.development? || Rails.env.test?` (fails closed
for staging and custom env names). Add a constraint example beside every mount snippet:

```ruby
authenticate :user, ->(u) { u.admin? } do   # Devise
  mount RailsPulse::Engine => "/rails_pulse"
end
```

Add a boot-time warning when enabled but unauthenticated outside `Rails.env.local?`.

## §20 — Deployment token uses `==`; CSRF makes the documented `curl` fail in production

Two coupled defects.

**(a) Timing attack.** `deployments_controller.rb:47` `provided == token` short-circuits on
the first differing byte. Same pattern in `fallback_http_basic_auth`
(`application_controller.rb:116`) and in the `authentication_method` example shipped at
`templates/rails_pulse.rb:253` — so the gem is teaching it.

**(b) The endpoint is unusable in production.** `ApplicationController <
ActionController::Base`, so it inherits `protect_from_forgery` from the host's
`default_protect_from_forgery`. `DeploymentsController` does **not**
`skip_before_action :verify_authenticity_token` — verified: only `assets_controller.rb:3`
does, which proves the callback is registered. Rails' `verified_request?` is
`valid_request_origin? && any_authenticity_token_valid?`, so a missing `Origin` does not
exempt. A CI `curl` carrying only `X-Rails-Pulse-Token` gets **422** — including the exact
`curl` printed at `templates/rails_pulse.rb:280-283`. `[INFERENCE]`: follows from documented
Rails semantics; not booted against a production-config host.

Tests cannot catch it: `test/dummy/config/environments/test.rb:29` sets
`allow_forgery_protection = false`.

**Fix:** `ActiveSupport::SecurityUtils.secure_compare` in both places and in the template
example. Add `skip_before_action :verify_authenticity_token, only: %i[create finish]` **and**
make the guard fail closed per §7 — adding the skip alone converts a fail-open endpoint into
a CSRF-exempt one. Add a controller test with `allow_forgery_protection = true`.

## §21 — `config.mount_dashboard` is completely inert

The only occurrences in the codebase are the accessor, default, and validator
(`configuration.rb:27`, `:98`, `:275-277`). **Nothing reads it.** The asset middleware
(`engine.rb:75-87`) and request middleware (`:89-91`) install unconditionally.

`docs/deployment-modes.md:56-61` instructs standalone users to set it `false` and explains it
"controls whether RailsPulse initializes dashboard-related middleware and assets". It does
not. Standalone users following the documented procedure still get the asset middleware in
their main app, relying entirely on commenting out `mount` — silently defeating the stated
isolation benefit.

**Fix:** honour it (guard the initializer and middleware insertion, reading lazily or via
`config.to_prepare`), or remove the setting and correct the doc.

## §22 — Nothing that protects upgrades runs in CI

**The root cause of the release's risk profile.** Each gap, with what it costs:

| Gap | Evidence | Risk |
|---|---|---|
| `test/migrations` not in `rake test` | `Rakefile:149` path list; CI calls `rake test` (`test.yml:78,126`) | The **only** suite simulating 0.3.x→0.4.0 is green-by-omission on every PR |
| `test_matrix` also omits it | `Rakefile:209` `base_test_paths` | Never runs on PG or MySQL — only via manual `rake test_release` step 13 |
| `test/upgrade_matrix/` empty, referenced nowhere | grep of `Rakefile bin/ .github/` → no hits | Dead directory implying coverage that does not exist |
| No separate-DB job anywhere | no workflow sets `connects_to`; `test/dummy/.../rails_pulse.rb:179` leaves it commented; `test/dummy/db/rails_pulse_migrate` absent | §4 — a BLOCKER — could only ever be caught by hand |
| `bin/test_generators` in no workflow | only `Rakefile:464` | §3 ships undetected |
| Coverage never enforced | `.simplecov:10-11` sets 90/80; `COVERAGE` appears nowhere in `test.yml`; `test_release` has no coverage step | Thresholds are decorative |
| `rake test_release` self-defeats | step 1 (`Rakefile:273` `appraisal install`) and step 2 (`sync_test_schema`) dirty the tree; step 4 (`:311-318`) fails if the tree is dirty | Trains the maintainer to skip the gate — and with it steps 12–14 |

**Coverage measured this run** (`rake test_coverage`, SQLite): **3068 runs, 0 failures**, but
SimpleCov **exits 2** — four files below the 80% per-file floor, and they are the wrong four:

| File | Line coverage |
|---|---|
| `lib/tasks/rails_pulse.rake` — contains §4's `record_rails_pulse_migrations_applied` | **20.58%** |
| `lib/rails_pulse/route_indexes.rb` — the adapter-divergent index of §12/§13 | **46.66%** |
| `lib/tasks/rails_pulse_assets.rake` | 50.00% |
| `lib/tasks/rails_pulse_tasks.rake` — contains `migrate_routes` | **54.16%** |

The mandatory backfill task and the function that silently corrupts `schema_migrations` are
the two least-covered files in the gem.

**Minimum additions to prevent another migration regression:**
1. Add `test/migrations` to `Rakefile:149` so it runs in every CI leg (sqlite × pg × mysql).
2. Add a **separate-database CI job**: set `connects_to`, populate
   `db/rails_pulse_migrate`, and run install → upgrade → `db:migrate:rails_pulse` →
   `migrate_routes` end to end. This is the only gap that would have caught §4.
3. Run `bin/test_generators` in CI.
4. Set `COVERAGE: true` on one representative cell and let SimpleCov's exit code fail it.
5. Add a gem-content assertion after `rake build`: no `.map` entries, migration count
   matches the working tree, pre-built assets present, size under threshold.
6. Move `test_release`'s git-status check to step 1, before anything mutates the tree.
7. Add baseline `test/support/schemas/v0_3_2.rb` — 0.3.2 has a distinct migration set and no
   fixture. (0.3.0 ≡ 0.3.1 schema, covered by `V031`; 0.3.3 covered.)

---

# MEDIUM

- **§23 — Install template contradicts gem defaults.** `templates/rails_pulse.rb:170-172`
  sets `capture_job_arguments = true` against a gem default of `false`
  (`configuration.rb:99`), its own comment two lines above, and `README.md:108`. Every
  fresh install opts *in* to persisting unfiltered job arguments. Also
  `full_retention_period` template `2.weeks` vs default `30.days` (README advertises 30);
  `rails_pulse_requests` 10 000 vs 50 000; `rails_pulse_queries` 500 vs 10 000.
  **The template is the hinge:** `ConfigUpdater` derives its entire upgrade append-set by
  parsing it (`config_updater.rb:60-62`), so template drift propagates to upgraders too.
  Highest-leverage single fix: reconcile the template with `Configuration#initialize` and add
  a test asserting they agree.
- **§24 — Template `max_table_records` omits both job tables**
  (`templates/rails_pulse.rb:311-318`), and `missing_hash_entries`
  (`config_updater.rb:118-131`) only injects keys present in the template — so upgraders
  never get them back. Distinct from §2 and needs fixing in both places.
- **§25 — Six supported options documented nowhere:** `job_tracking_mode`, `job_adapters`
  (the only way to disable the Sidekiq middleware), `logger`, `async`, `warn_on_stale_summaries`,
  and `mount_dashboard` (documented only in `deployment-modes.md`, absent from the template).
  Adding commented entries to the template also surfaces them to upgraders, since
  `ConfigUpdater`'s `ASSIGNMENT` regex matches commented assignments.
- **§26 — Separate-DB docs never mention `config.connects_to`.**
  `docs/database_setup.md:31-70` and `install_generator.rb:67-90` list three steps, none of
  which is "uncomment `config.connects_to`" — yet `application_record.rb:5` only reroutes if
  it is set, and the template ships it **commented out** (`:181-183`). Following the
  generator's own output yields a correctly-created, entirely **empty** Pulse database while
  all models write to the primary connection.
- **§27 — "Restart all processes together" absent from generator output.** Present in
  CHANGELOG, README, and `database_setup.md`, but `say_next_steps`
  (`upgrade_generator.rb:218-232`) ends with a bare singular *"Restart your Rails server"*.
  Kamal/Heroku operators read terminal output, not changelogs. (Now fixed in
  `post_install_message`; still needs adding to the generator.)
- **§28 — `AddLocationToExceptionGroups` crashes `db:migrate` for users who follow the
  generator's own advice.** `20260823000001:3-7` guards only on `column_exists?`, not
  `table_exists?`, while `upgrade_generator.rb:113-115` explicitly tells users they may
  delete the copied exceptions migration. Then `add_column` raises and aborts the upgrade
  midway. The advice is also wrong for separate-DB hosts, where the schema file creates the
  tables regardless. Consider consolidating `20260506000001` and `20260823000001` — no
  released version ever had these tables, so the split (and the backdating) serves nothing.
- **§29 — `migrate_routes` is unbatched, unbounded, non-resumable.**
  `route_controller_action_backfiller.rb:9-11` does per-row router recognition plus 3–4
  queries via `find_each`; `route_migrator.rb:10-12` does a second full pass;
  `route_merger.rb:28` issues a per-merge `update_all` on requests. No batching, no progress
  output, no transaction boundary, no "safe to re-run" message. The installs that most need
  this task have the largest `rails_pulse_routes` (0.3.x stored literal paths).
- **§30 — Migration `20260610000002` is irreversible and that is undocumented.**
  `:65-67` raises `IrreversibleMigration`; `:58` drops `routes.method`; `:104` deletes merged
  rows. `db:rollback STEP=3` rolls back the two later migrations then raises, leaving a
  half-rolled-back schema. Recovery is restore-from-backup only. (Now stated in the
  CHANGELOG; should also appear in `say_route_backfill_warning`.)
- **§31 — Brakeman config weakens coverage.** `config/brakeman.yml:58-63` skips
  `CheckForgerySetting` with the note "CSRF protection is handled by host app" — false, since
  engine controllers inherit `ActionController::Base`; this is precisely why §20(b) is
  invisible. `:36` `min_confidence: 1` hides Weak findings. Also `rake brakeman` **currently
  exits 1** on one unignored Medium false positive (`route_migrator.rb:122`, safe:
  `quote_table_name` + `to_i`), so `test_release` step 6 is red today.
- **§32 — `ignored` exception groups still take the full write path.**
  `exception_capture_service.rb:63-64` skips only `create_occurrence`; the upsert still bumps
  `last_seen_at` and `occurrence_count`. "Ignore" suppresses ~1 of 4 statements, and the
  rising count with zero occurrence rows is internally inconsistent.
- **§33 — Dashboard runs up to 50 router recognitions per request.**
  `application_controller.rb:7` → `:137` → `route.rb:73-83` loads 25 null-action routes and
  calls `RouteRecognizer` on each, which tries authenticated then unauthenticated
  (`route_recognizer.rb:29`), each building a full `Rack::MockRequest.env_for`. Unrecognised
  404 paths keep `controller_action` NULL permanently, so this cost is paid forever — on every
  turbo-frame and chart fetch. Memoise, or skip when `partial_request?`.
- **§34 — Two icons missing from the shipped bundle.** `scripts/build-icons.js:153,158`
  scans only `app/views/**/*.html.erb` and matches only `lucide_icon`, but the codebase calls
  `rails_pulse_icon` (`icon_helper.rb:5`). Missing: `triangle-alert`
  (`_operation_details_popover.html.erb`, 7 call sites) and `help-circle`
  (`status_helper.rb:63`, a `.rb` file the scanner cannot see). `REQUIRED_ICONS` has
  `alert-triangle`, not `triangle-alert`, so a rebuild does **not** fix it;
  `icon_controller.js:47-50` logs a console error. Widen the scanner to
  `app/**/*.{erb,rb}`, match both helper names, and make an unresolvable icon a hard build
  failure.
- **§35 — `install_migrations` is dead code that reports success.**
  `migration_installer.rb:73-75` points `source_dir` at `db/migrate`, which does not exist in
  the gem; `migration_order` (`:64-71`) names four files that exist nowhere. Wired at
  `rails_pulse_tasks.rake:3-5` and reachable via `rails_pulse:install`. A user running it
  gets "Copying migrations..." and an empty directory.
- **§36 — `bin/benchmark` measures the wrong code path.** `:86` sets
  `action_dispatch.request.parameters`, but `RequestCollector` reads
  `path_parameters` (`request_collector.rb:43`). So `controller_action` is always nil and
  normalisation always takes its pass-through branch — the benchmark exercises the 404 path
  and reports it as normal. No `track_exceptions` or `track_jobs` scenario exists, so 0.4.0's
  headline code is entirely unmeasured, and §6 could not have been caught.
- **§37 — `standalone` minimal branch is dead code.** `lib/rails_pulse_server.ru:9-19`
  requires only `active_support`/`active_record` then `require "rails_pulse"`, which raises
  `NameError: uninitialized constant Rails` because `engine.rb:57` subclasses
  `::Rails::Engine`. So the documented `DATABASE_URL`-only Kamal accessory path
  (`deployment-modes.md:121-140`) never reaches its own code. Also `:2` keys app detection on
  a **CWD-relative** `test/dummy/config/environment.rb`.
- **§38 — Website: `track_jobs` documented as defaulting to `true`.** `job-adapters.mdx:66`,
  `features.mdx:45` ("No Configuration Required… access the jobs dashboard at
  `/rails_pulse/jobs`"), `faq.mdx:67`. It is `false` (`configuration.rb:59`) and
  `config/routes.rb:21` gates the entire jobs route block on it, so `/rails_pulse/jobs`
  **404s out of the box**.
- **§39 — Website: route identity change breaks published tagging examples.**
  `advanced.mdx:104` and `tagging.mdx:53` both publish
  `RailsPulse::Route.find_by(path: "/api/users")`. Under `[controller_action, path]` several
  rows share one path, so this returns an arbitrary row and tags the wrong route
  non-deterministically. Also `advanced.mdx:130-138`'s `max_table_records` example omits both
  exception tables — and the hash is replaced wholesale, not merged.
- **§40 — Website: MySQL CI claim is false.** `databases.mdx:68` says MySQL "is excluded from
  Rails Pulse's CI test suite (tested locally only)". There is a dedicated `mysql:` job
  (`test.yml:80-127`). The narrower-matrix caveat is fair; the headline is wrong.
- **§41 — `CONTEXT.md` has no route-identity vocabulary.** It defines the exception domain
  thoroughly but nothing for Route, `controller_action`, `http_methods`, or path
  normalisation — 0.4.0's other headline change, and the terms `migrate_routes` is built
  around. `docs/adr/` likewise has three exception ADRs and none for the identity change,
  which was the larger design decision.

---

# LOW / NIT

- `redirect_back` at `application_controller.rb:53,70` and `tags_controller.rb:22,32` relies
  on the host's `raise_on_open_redirects`; pass `allow_other_host: false` explicitly.
- `csp_test` route is registered unconditionally in production (`config/routes.rb:41`),
  unlike `exceptions`/`jobs` which are config-gated. Gate on `Rails.env.local?`.
- Asset version-strip regex `asset_server.rb:17` accepts `..` in the version segment. **Not
  exploitable** — `Rack::Files` applies `clean_path_info` — but it constructs a traversal
  string and relies on an external sanitizer to undo it.
- Engine forces `style-src-attr 'unsafe-inline' 'unsafe-hashes'` via many hard-coded inline
  `style=` attributes; the gem's own `csp_test_controller.rb:24` concedes this. Undocumented.
  Nonce discovery returns `nil` silently on failure (`csp_helper.rb:42-43`), emitting
  `nonce=""`.
- Standalone session cookie lacks `secure: true` (`lib/rails_pulse_server.ru:97-101`).
  `SECRET_KEY_BASE` handling is correct (refuses to boot without it).
- `add_http_method` (`route.rb:63-68`) is read-modify-write; concurrent first-sightings of
  different verbs lose one. Self-heals on the next request; arguably just document it.
- Dependabot has no `npm` entry (`.github/dependabot.yml`) despite `npm ci` in three CI jobs;
  `echarts` and `flatpickr` ship straight into `rails-pulse.js`.
- `engine.rb:66-68` globs `lib/rails_pulse/tasks/**/*.rake`, which matches nothing; the real
  tasks load only via `Rails::Engine`'s automatic `lib/tasks/*.rake`.
- `README.md` has no requirements section, no deployment-modes/standalone coverage, no link to
  `docs/`, and no generic upgrade pointer.
- Stray tracked file `rails_pulse/test/system/dashboard_index_page_test.rb` in a nested
  `rails_pulse/` directory at the repo root — never executed. Delete.
- Website: `Layout.astro:16` ships `<meta name="description" content="Astro description">` on
  every docs page (confirmed live), with no canonical tag. `index.astro:32,38` point
  `og:url`/`twitter:url` at GitHub instead of railspulse.com. `src/components/home/` holds
  unreferenced components, several still containing Lorem ipsum.
- `bin/publish_gem` warns about missing assets but never rebuilds and never inspects gem
  contents; on push failure it leaves a stray root-level `*.gem` that is not gitignored.
  **Verified:** built assets are currently byte-identical to a fresh production build
  (`rails-pulse.js` 2,296,238 bytes, `rails-pulse.css` 99,088 bytes), so **no rebuild is
  needed** before publishing.

---

# Verified clean

Worth recording, so these are not re-litigated:

- **Migration idempotency across every 0.3.x baseline.** Every migration guards with
  `column_exists?`/`table_exists?`/`index_exists?`. Re-running the full set against a current
  0.4.0 schema is a no-op. No missing guard found.
- **Route-merge child-row safety.** Both merge paths reassign `requests.route_id` and
  reassign-or-merge summaries (respecting the unique index) *before* deleting the loser row
  (`20260610000002:100-137`, `route_merger.rb:26-31`). No orphans, no unique violations.
- **The backdated `20260506000001` is harmless.** Migrations are copied verbatim with
  timestamps preserved (`upgrade_generator.rb:346-351`), the engine never appends
  `db/rails_pulse_migrate` to `paths["db/migrate"]`, and ActiveRecord applies out-of-order
  pending versions in ascending order. `schema.rb`'s version marker stays monotonic. Worth
  consolidating for tidiness (§28), not for correctness.
- **`migrate_routes` respects `connects_to`** — goes through `RailsPulse::Route.connection`.
- **Exception cleanup wiring is complete and correct**, with no orphans in either direction,
  and `preserve` is honoured in all four delete paths (`cleanup_service.rb:221-224,236,250`).
  Tested at `cleanup_service_test.rb:464-609`. The *caps* are the problem (§2, §16), not the
  wiring.
- **`occurrence_count` is genuinely atomic** — incremented in the upsert's conflict clause
  (`exception_capture_service.rb:114-170`). No read-modify-write.
- **Route find-or-create is race-safe by construction** — `Route.insert` is `insert_all` with
  `on_duplicate: :skip` → `ON CONFLICT DO NOTHING` / `INSERT IGNORE`, so `RecordNotUnique` is
  never raised and correctly needs no rescue. Depends on the indexes existing (§17).
- **Ransack is properly locked down** — every model defines narrow explicit
  `ransackable_attributes` and `ransackable_associations`; `ransackable_scopes` left at `[]`;
  all sort handling goes through `case` allow-lists with `dir` coerced.
- **No XSS** — no `raw`/`html_safe`/`<%==` in any view; the single `sanitize` call is
  tag-restricted; chart payloads go through `content_tag(data:)`.
- **Dev-dependency placement is correct** — `sqlite3`, `pg`, `mysql2`, `importmap-rails`,
  `css-zero` are genuinely dev-only; zero runtime requires. (`config/importmap.rb` is dead
  code but harmless.)
- **Prerelease version handling works end to end** — `bin/bump_version:45` and `bin/release`
  enforce dot-separated suffixes; `0.4.0.pre.1` matches the asset-version regex
  (`asset_server.rb:16`), so the bump busts CDN caches and the middleware still resolves.
- **Locked dev dependencies are current** with no outstanding advisories: rails 8.1.3,
  rack 3.2.6, nokogiri 1.19.3, ransack 4.3.0, pg 1.6.0, sqlite3 2.9.5.
- **`RouteMigrator`** handles both `RecordNotUnique` cases including stale PK sequences, with
  correct per-adapter resync and an explicit MySQL nested-transaction guard
  (`route_migrator.rb:93-127`). Careful work.
- **JS toolchain green** — `npm run lint:js` clean, `npm run test:js` 13 files / 117 tests pass.
- **`.env` hygiene fine** — gitignored, only `.env.example` tracked, contains only local DB
  knobs, no credentials.

---

# Implementation plan

Findings are grouped into PRs by **area and file ownership**, not by severity. This
avoids dangerous intermediate states (e.g. adding a CSRF skip to the deployments
endpoint without simultaneously fixing its fail-open guard) and keeps the total PR
count manageable. PRs 1–6 can mostly be developed in parallel since they touch
different files.

| PR | Area | Sections | Key files | Status |
|---|---|---|---|---|
| 1 | **Security: EXPLAIN + actual_sql** | §1, §11 | `explain_plan_analyzer.rb`, `brakeman.ignore`, `configuration.rb`, `operation_subscriber.rb` | [PR #199](https://github.com/railspulse-org/rails_pulse/pull/199) |
| 2 | **Security: Deployments + auth** | §7, §19, §20 | `deployments_controller.rb`, `application_controller.rb`, `configuration.rb` | Not started |
| 3 | **Failure isolation** ("Pulse never breaks the host") | §5, §6, §8 | `job_run_collector.rb`, `tracker.rb`, `request_collector.rb` | Not started |
| 4 | **Shipped initializer + config drift** | §2, §23, §24, §25 | delete `config/initializers/rails_pulse.rb`, `configuration.rb`, `templates/rails_pulse.rb`, `config_updater.rb` | Not started |
| 5 | **Migration safety** | §3, §4, §17, §28, §29 | `upgrade_generator.rb`, `rails_pulse.rake`, `rails_pulse_tasks.rake`, `route_controller_action_backfiller.rb` | Not started |
| 6 | **CI + compatibility** | §22, §12, §13, §14 | `Rakefile`, `test.yml`, `route_indexes.rb`, `gemspec` | Not started |
| 7 | **Website** | §9, §38, §39, §40 | separate repo: `/Users/scott/studioomni/rails_pulse_website` | Not started |
| 8 | **Everything else** | remaining MEDIUMs, LOWs, NITs | various | Not started |

**Merge order:** PR 1 first — the only finding where a dashboard page view can silently
re-execute a production `DELETE`. PR 5 is what stops the recurring migration breakage.
PR 6 should land before PRs 1–5 are considered fully verified, since it adds the CI
coverage that would catch regressions in each of them.

**Consider shipping `0.4.0.pre.1` as a genuine prerelease** — RubyGems will not resolve it
for `gem "rails_pulse"` without an explicit version — and asking one separate-DB user and one
MySQL user to exercise the upgrade before `0.4.0` final. Those are the two combinations with
neither automated coverage nor a clean bill of health here.
