# Rails Pulse Gem Release Process

This document outlines the steps to release a new version of the Rails Pulse gem to RubyGems.org.

## Quick Start: Automated Release

For a fully guided release process, use the interactive release script:

```bash
bin/release
```

This script will walk you through all the steps below interactively. Continue reading for manual release instructions or to understand what each script does.

## Individual Release Scripts

For more control, you can run individual scripts:

```bash
bin/bump_version <version>      # Update version files
bin/commit_release <version>    # Create version bump commit
bin/tag_release <version>       # Create annotated git tag
bin/push_release [--wait-ci]    # Push and optionally wait for CI
bin/publish_gem                 # Build and publish to RubyGems
```

Run any script with `--help` for more information.

## Pre-Release Checklist

### 1. Run Comprehensive Pre-Release Tests

Run the automated pre-release validation task that performs all necessary checks:

```bash
rake test_release
```

This task will automatically:
1. ✅ Check git status (no uncommitted changes)
2. ✅ Run RuboCop linting
3. ✅ Install Node dependencies
4. ✅ Build and verify production assets
5. ✅ Verify gem builds correctly
6. ✅ Run generator tests (install/upgrade for both database setups)
7. ✅ Run full test matrix across all databases and Rails versions with system tests

**Expected output**: `🎉 All pre-release checks passed!`

If any checks fail, fix the issues and re-run `rake test_release` until all checks pass.

### 2. Update Version Number

Edit the version in `lib/rails_pulse/version.rb`:

```ruby
module RailsPulse
  VERSION = "0.2.0"  # Update this
end
```

Then update all Gemfile.lock files to reflect the new version:

```bash
# Update Rails 7.2 gemfile.lock
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle install

# Update Rails 8.0 gemfile.lock
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle install

# Verify version updated in all lock files
grep "rails_pulse" gemfiles/*.gemfile.lock
```

### 3. Update Release Documentation

- Document new features, bug fixes, and breaking changes
- Update README.md if there are new installation steps or configuration changes
- Consider updating the gem description in `rails_pulse.gemspec` if significant features were added

## Release Steps

### 1. Commit Version Bump

Commit the version change directly to main (branch protection rules are bypassed for maintainers):

```bash
# Add the version file and updated Gemfile.lock files
git add lib/rails_pulse/version.rb
git add gemfiles/rails_7_2.gemfile.lock
git add gemfiles/rails_8_0.gemfile.lock

# Commit with clear message
git commit -m "Bump version to v0.2.0"

# Push to main (will bypass branch protection)
git push origin main
```

### 2. Wait for CI to Pass

Verify that all GitHub Actions are green:
- **Test Suite**: Tests across SQLite3 + PostgreSQL with Rails 7.2 and 8.0
- **Lint**: RuboCop validation
- **Build**: Asset building and gem compilation

Check the Actions tab: https://github.com/railspulse/rails_pulse/actions

### 3. Create Git Tag

Create and push an annotated tag with release notes:

```bash
# Create annotated tag with detailed release notes
git tag -a v0.2.0 -m "Release v0.2.0

## New Features
- Query performance analysis system
- N+1 query detection and alerts
- Database index recommendations
- Interactive analysis UI with real-time refresh

## Improvements
- Enhanced MySQL compatibility with proper index constraints
- Cross-database support improvements
- Better error handling and user feedback

## Bug Fixes
- Fixed turbo frame rendering issues
- Resolved MySQL index key length compatibility

## Breaking Changes
- None

## Upgrade Notes
- Run 'rails generate rails_pulse:upgrade' after updating
"

# Push tag to trigger any release automation
git push origin v0.2.0
```

### 4. Build and Release Gem

Use Bundler's release tasks:

```bash
# Ensure assets are built for production
npm run build

# Build the gem package
rake build

# Release to RubyGems (requires authentication)
rake release
```

**Note**: The `rake release` command will:
1. Build the gem package
2. Create a Git tag (if not already created)
3. Push the tag to GitHub
4. Push the gem to RubyGems.org

### 5. Create GitHub Release

1. Go to [GitHub Releases](https://github.com/railspulse/rails_pulse/releases)
2. Click "Create a new release"
3. Select the tag you just created (v0.2.0)
4. Title: "Rails Pulse v0.2.0"
5. Description: Copy the release notes from your tag message
6. Attach the built gem file (`pkg/rails_pulse-0.2.0.gem`) if desired
7. Click "Publish release"

## Post-Release Steps

### 1. Verify Release

- Check that the new version appears on [RubyGems.org](https://rubygems.org/gems/rails_pulse)
- Test installation in a fresh Rails app:

```bash
# In a new Rails app
gem install rails_pulse
rails generate rails_pulse:install
```

### 2. Update Documentation

- Update any version-specific documentation
- Ensure installation instructions are current
- Update example applications if needed

### 3. Announce Release

Consider announcing the release through:
- GitHub Discussions
- Rails community forums
- Social media
- Company blog/newsletter

## Troubleshooting

### Authentication Issues

If you get authentication errors when pushing to RubyGems:

```bash
# Set up RubyGems credentials (interactive)
gem signin

# Or use API key directly
gem push pkg/rails_pulse-0.2.0.gem --key your-api-key
```

### Branch Protection Bypass Issues

If you get errors about branch protection when pushing to main:

- Ensure you have **admin** or **maintainer** permissions on the repository
- The push output should show "Bypassed rule violations" if successful
- If blocked, create a pull request instead and merge after CI passes

### Version Conflicts

If the version already exists on RubyGems:

1. Increment the version number
2. Commit the change
3. Create a new tag
4. Try the release again

### Failed Tests

If tests fail during release:

1. Fix the failing tests
2. Ensure all changes are committed
3. Re-run the release process

## Emergency Rollback

If a release has critical issues:

### 1. Yank the Gem (Use Sparingly)

```bash
gem yank rails_pulse -v 0.2.0
```

⚠️ **Warning**: Only yank gems in extreme circumstances as it breaks existing installations.

### 2. Quick Patch Release

For less severe issues, release a patch version:

1. Create a hotfix branch from the problematic tag
2. Fix the issue
3. Bump to patch version (e.g., 0.2.1)
4. Follow normal release process

## Version Guidelines

Rails Pulse follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking changes, major feature rewrites
- **MINOR** (0.1.0): New features, backwards-compatible changes
- **PATCH** (0.0.1): Bug fixes, security patches

### Examples:
- New analysis features: Minor version bump
- Bug fixes: Patch version bump
- Breaking API changes: Major version bump
- Database schema changes: Consider major/minor based on backwards compatibility

## Security Releases

For security-related releases:

1. **Do not** discuss the vulnerability publicly before release
2. Follow the same release process but prioritize speed
3. Clearly mark the release as a security update
4. Consider backporting fixes to older supported versions
5. Notify users through appropriate security channels

## Support Policy

- **Latest Minor Version**: Full support and new features
- **Previous Minor Version**: Security patches and critical bug fixes
- **Older Versions**: Security patches only (case-by-case basis)

Always encourage users to upgrade to the latest version for the best experience and security.

## Release Automation Scripts

Rails Pulse includes several automation scripts to streamline the release process.

### Interactive Release Manager: `bin/release`

The primary release tool is an interactive script that guides you through the entire process:

```bash
bin/release
```

**What it does:**
1. Pre-flight checks (git status, branch, up-to-date with remote)
2. Prompts for new version number with validation
3. Updates version files and Gemfile.locks
4. Optionally runs pre-release tests (rake test_release)
5. Creates git commit for version bump
6. Opens editor for release notes
7. Creates annotated git tag
8. Pushes to GitHub
9. Optionally waits for CI to complete (requires `gh` CLI)
10. Builds and publishes gem to RubyGems
11. Opens GitHub releases page in browser

**Features:**
- ✅ Colorized output for clear visual feedback
- ✅ Confirms before destructive operations
- ✅ Can be interrupted and resumed
- ✅ Validates all inputs
- ✅ Shows helpful error messages

### Individual Scripts

Each step can also be run independently:

#### `bin/bump_version <version>`

Updates version number in all necessary files:
- `lib/rails_pulse/version.rb`
- `gemfiles/rails_7_2.gemfile.lock`
- `gemfiles/rails_8_0.gemfile.lock`

```bash
bin/bump_version 0.3.0
```

#### `bin/commit_release <version>`

Creates a git commit for the version bump with a standardized message.

```bash
bin/commit_release 0.3.0
# Commits: "Bump version to v0.3.0"
```

#### `bin/tag_release <version>`

Creates an annotated git tag with release notes.

```bash
# Opens editor for release notes
bin/tag_release 0.3.0

# Or provide notes inline
bin/tag_release 0.3.0 --notes "Bug fixes and improvements"
```

#### `bin/push_release [--wait-ci]`

Pushes commits and tags to GitHub, optionally waiting for CI to complete.

```bash
# Push without waiting
bin/push_release

# Push and wait for CI (requires gh CLI)
bin/push_release --wait-ci
```

#### `bin/publish_gem`

Builds and publishes the gem to RubyGems.org.

```bash
bin/publish_gem
```

**Prerequisites:**
- Assets must be built (`npm run build`)
- Must be authenticated with RubyGems (`gem signin`)

### Script Help

Every script has built-in help:

```bash
bin/release --help
bin/bump_version --help
bin/commit_release --help
bin/tag_release --help
bin/push_release --help
bin/publish_gem --help
```

### Example Workflows

**Full automated release:**
```bash
bin/release
# Follow the interactive prompts
```

**Manual step-by-step release:**
```bash
# 1. Update version
bin/bump_version 0.3.0

# 2. Run tests
rake test_release

# 3. Commit changes
bin/commit_release 0.3.0

# 4. Create tag
bin/tag_release 0.3.0

# 5. Push to GitHub
bin/push_release --wait-ci

# 6. Publish gem
bin/publish_gem
```

**Quick patch release (skip tests):**
```bash
bin/bump_version 0.2.1
bin/commit_release 0.2.1
bin/tag_release 0.2.1 --notes "Critical bug fix for X"
bin/push_release
bin/publish_gem
```
