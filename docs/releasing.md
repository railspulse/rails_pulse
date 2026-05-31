# Rails Pulse Release Process

## Quick Start

Run the interactive release script:

```bash
bin/release
```

This guides you through the entire release process automatically.

To capture the full session as an HTML report (useful for reviewing step output afterward):

```bash
bin/release-log   # requires: brew install aha
```

Output is saved to `tmp/release-YYYYMMDD-HHMMSS.html` and opened automatically when the session ends.

## Manual Release

If you prefer to run steps individually:

### 1. Pre-Release Testing

Run comprehensive pre-release tests:

```bash
rake test_release
```

This validates (14 steps total):
- Appraisal gemfile sync
- Test schema sync
- Dummy app migration verification
- Git status (clean working directory)
- Code linting (RuboCop)
- Brakeman security scan
- JavaScript unit tests (`npm run test:js`)
- Asset building
- Gem build verification
- Generator tests (install + upgrade)
- Full test matrix (all databases × Rails versions + system tests)

### 2. Update Version

```bash
bin/bump_version 0.3.0
```

Updates:
- `lib/rails_pulse/version.rb`
- `Gemfile.lock`
- `gemfiles/rails_7_2.gemfile.lock`
- `gemfiles/rails_8_0.gemfile.lock`

**Pre-release versions:** use dots, not hyphens — `0.3.0.pre.1`, `0.3.0.beta.1`, `0.3.0.rc.1`.

### 3. Commit Changes

```bash
bin/commit_release 0.3.0
```

Creates commit: `Bump version to v0.3.0`

### 4. Create Git Tag

```bash
bin/tag_release 0.3.0
```

Opens your editor for release notes. Optionally generates a draft from git history.

Or provide notes inline:

```bash
bin/tag_release 0.3.0 --notes "Bug fixes and improvements"
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
bin/bump_version 0.3.0
bin/commit_release 0.3.0
bin/tag_release 0.3.0
bin/push_release --wait-ci
bin/publish_gem
```

**Quick patch (skip tests):**
```bash
bin/bump_version 0.2.1
bin/commit_release 0.2.1
bin/tag_release 0.2.1 --notes "Critical bug fix"
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
gem yank rails_pulse -v 0.3.0  # Use sparingly!
```

## Version Guidelines

Rails Pulse follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking changes
- **MINOR** (0.1.0): New features, backwards-compatible
- **PATCH** (0.0.1): Bug fixes, security patches

Pre-release suffixes use dots: `0.3.0.pre.1`, `0.3.0.beta.1`, `0.3.0.rc.1`
