# Rails Pulse Release Process

## Quick Start

Run the interactive release script:

```bash
bin/release
```

This guides you through the entire release process automatically.

To capture the full session as an HTML report (useful for reviewing step output afterward):

```bash
bin/release-log   # requires aha: brew install aha / sudo pacman -S aha / apt install aha
```

Output is saved to `tmp/release-YYYYMMDD-HHMMSS.html` and opened automatically when the session ends.

## Patch Release From a Stable Branch

`main` carries the next release. When a fix has to ship for an earlier series and `main`
already holds work that is not patch material (a new table, a raised Ruby or Rails floor),
cut the patch from a stable branch instead.

A stable branch is named `X-Y-stable` (`0-4-stable` releases 0.4.x) and starts at the
series' latest tag. It is long-lived: the next patch in the series reuses it.

```bash
git switch -c 0-4-stable v0.4.1      # first patch in the series only
git push -u origin 0-4-stable
```

1. Open the fix as a pull request against the stable branch. CI runs for pull requests
   and pushes that target `main` or any `*-stable` branch.
2. Once merged, run `bin/release` on the stable branch. It accepts `main` and
   `X-Y-stable`, refuses a version outside the branch's series, and keeps a patch to an
   older series from taking GitHub's "Latest" badge from a newer release.
3. Merge the stable branch into `main`, so `main` carries the fix and the released
   version's changelog section. Where `main` has diverged, resolve towards `main`'s
   structure and keep `main`'s version number if it is already higher.

## Manual Release

If you prefer to run steps individually:

### 1. Pre-Release Testing

Run comprehensive pre-release tests:

```bash
rake test_release
```

This runs 15 steps, in order:

1. Git status (clean working directory)
2. Appraisal gemfile sync
3. Test schema sync
4. Dummy app migration verification
5. RuboCop
6. Rails.env branching check under `app/` (`rake check_app_env_branching`)
7. Brakeman security scan
8. Node dependency install
9. ESLint (`npm run lint:js`)
10. JavaScript unit tests (`npm run test:js`)
11. Production asset build
12. Gem build verification
13. Generator tests (install + upgrade)
14. Migration regression tests (`rake test_migrations`)
15. Full test matrix (all databases × Rails versions)

The list lives in `Rakefile` under `test_release`; keep this section in step with it.

#### Separate-DB Upgrade Smoke Test

**Required when the release includes any new migration.** The automated suite runs
single-database only; this script covers the other path:

```bash
DB=sqlite3 bin/test_separate_database_upgrade
DB=postgresql bin/test_separate_database_upgrade      # POSTGRES_* as for rake test
BASELINE=V027 bin/test_separate_database_upgrade      # oldest baseline; default V032
```

It boots `test/dummy` with `config.connects_to` pointing at the `rails_pulse` database,
loads the baseline schema into that database, inserts a route, a request and a SQL
operation so data-backfill migrations have rows to process, then runs what a host would:
`rails generate rails_pulse:upgrade` without `--database` (asserting it detects
`separate`), `db:migrate:rails_pulse`, `rails_pulse:migrate_routes`, and
`rails_pulse:status`, which must exit 0 with the schema up to date and routes backfilled.
CI runs the same script on SQLite and PostgreSQL; it restores the dummy app's files and
database afterwards.

#### Verify assets and version-scoped caching

Dashboard assets are served from `/rails-pulse-assets/<gem-version>/...`, so the
version bump is what busts any CDN cache holding those paths as immutable. After
`assets:precompile`, confirm the logs include `[RailsPulse] Installed N dashboard
assets`.

`npm run build` is a manual step whose output is committed, so confirm the built
files under `public/rails-pulse-assets/` match their sources before tagging.

> Release-specific notes belong in the CHANGELOG's `[Unreleased]` section, not in
> this file.

### 2. Update Version

```bash
bin/bump_version X.Y.Z
```

Updates:
- `lib/rails_pulse/version.rb`
- `Gemfile.lock`
- every `gemfiles/rails_*.gemfile.lock` (discovered from the directory, so a newly
  added Rails version is picked up automatically)
- `test/dummy/Gemfile.lock`

**Pre-release versions:** use dots, not hyphens — `X.Y.Z.pre.1`, `X.Y.Z.beta.1`, `X.Y.Z.rc.1`.

### 3. Commit Changes

```bash
bin/commit_release X.Y.Z
```

Creates commit: `Bump version to vX.Y.Z`

### 4. Create Git Tag

```bash
bin/tag_release X.Y.Z
```

Opens your editor for release notes. Optionally generates a draft from git history.

Or provide notes inline:

```bash
bin/tag_release X.Y.Z --notes "Bug fixes and improvements"
```

### 5. Push to GitHub

```bash
bin/push_release --wait-ci
```

Pushes commits and tags, optionally waits for CI to complete (requires `gh` CLI).

### 6. Publish Gem

```bash
bin/publish_gem
```

Prerequisites:
- Assets built: `npm run build`
- Authenticated with RubyGems: `gem signin`

Builds the gem, publishes to RubyGems.org, and moves the `.gem` file to `pkg/`.

### 7. Create GitHub Release

Visit the GitHub releases page (automatically opens if using `bin/release`):
https://github.com/railspulse/rails_pulse/releases/new

## Individual Scripts

Each script has detailed help:

```bash
bin/release --help
bin/release-log --help
bin/bump_version --help
bin/commit_release --help
bin/tag_release --help
bin/push_release --help
bin/publish_gem --help
```

## Quick Reference

**Full automated release (with HTML log):**
```bash
bin/release-log
```

**Full automated release:**
```bash
bin/release
```

**Manual step-by-step:**
```bash
rake test_release
bin/bump_version X.Y.Z
bin/commit_release X.Y.Z
bin/tag_release X.Y.Z
bin/push_release --wait-ci
bin/publish_gem
```

**Emergency patch only (skips `rake test_release`; CLAUDE.md requires it for every normal release):**
```bash
bin/bump_version X.Y.Z
bin/commit_release X.Y.Z
bin/tag_release X.Y.Z --notes "Critical bug fix"
bin/push_release
bin/publish_gem
```

## Troubleshooting

**RubyGems authentication:**
```bash
gem signin
```

**Assets not built:**
```bash
npm run build
```

**Version already exists:**
Increment version and try again — RubyGems doesn't allow re-publishing.

**CI failed:**
Fix issues, commit fixes, and re-run from step 5.

**Rollback (emergency only):**
```bash
gem yank rails_pulse -v X.Y.Z  # Use sparingly!
```

## Version Guidelines

Rails Pulse follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking changes
- **MINOR** (0.1.0): New features, backwards-compatible
- **PATCH** (0.0.1): Bug fixes, security patches

Pre-release suffixes use dots: `X.Y.Z.pre.1`, `X.Y.Z.beta.1`, `X.Y.Z.rc.1`

### Public API

"Breaking" is judged against [`docs/api.md`](api.md), not against the whole codebase.
Renaming, moving, or changing the signature of something listed there is a MAJOR change.
Everything not listed — `Cards::*`, `Charts::*`, `Tables::*`, controllers, concerns, and
`Tracker`/`SchemaCheck` internals beyond the methods `docs/api.md` names — can change shape in
a MINOR release. Adding something to the public surface, or widening a documented contract, is
still just a MINOR change. When a change touches something on that page, update the page in
the same PR.
