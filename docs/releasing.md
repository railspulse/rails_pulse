# Rails Pulse Gem Release Process

This document outlines the steps to release a new version of the Rails Pulse gem to RubyGems.org.

## Pre-Release Checklist

### 1. Test Across Supported Environments

Run the full test matrix locally to ensure compatibility:

```bash
# Test across all supported database and Rails versions locally
rake test:matrix
```

### 2. Build and Test Assets

Ensure all frontend assets build correctly:

```bash
# Install Node dependencies
npm install

# Build production assets
npm run build

# Verify assets were built
ls -la public/rails-pulse-assets/
```

### 3. Run Full Test Suite

```bash
# Run all tests (this will also validate the CI setup)
rake test_matrix

# Check that the gem builds successfully
gem build rails_pulse.gemspec
```

### 4. Update Version Number

Edit the version in `lib/rails_pulse/version.rb`:

```ruby
module RailsPulse
  VERSION = "0.2.0"  # Update this
end
```

### 5. Update Release Documentation

- Document new features, bug fixes, and breaking changes
- Update README.md if there are new installation steps or configuration changes
- Consider updating the gem description in `rails_pulse.gemspec` if significant features were added

## Release Steps

### 1. Commit Version Bump

Commit the version change directly to main (branch protection rules are bypassed for maintainers):

```bash
# Add the version file
git add lib/rails_pulse/version.rb

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
