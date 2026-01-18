## Summary

Adds Rails 8.1 support to Rails Pulse gem by updating Appraisals configuration, fixing compatibility issues in upgrade generator tests, and updating all documentation to reflect the new Rails version support.

## Type of Change

<!-- Mark the relevant option with an [x] -->

- [x] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Performance improvement
- [ ] Code refactoring (no functional changes)
- [x] Documentation update
- [x] Test improvements
- [x] Build/CI improvements

## Changes Made

<!-- List the specific changes made in this PR -->

- **Added Rails 8.1 Appraisal configuration** with Pagy 43 (Method API)
- **Fixed Rails 8.1 compatibility issues** in upgrade generator tests by:
  - Adding missing `minitest` and `ostruct` development dependencies
  - Updating mocking syntax from `ActiveRecord::Base.stub` to Mocha's `stubs/unstub` methods
  - Fixing `run_generator` calls to use new Rails 8.1 syntax with args array and config hash
- **Updated all documentation** to include Rails 8.1 support:
  - PR template: Added Rails 8.1 testing checkboxes and Appraisals configuration requirements
  - README: Updated version badge, Ruby requirement, and all testing documentation
  - PLAN: Fixed migration version for broader Rails compatibility
- **Restored accidentally deleted migration file** (`20260117000000_optimize_rails_pulse_indexes.rb`)
- **Updated gemspec** with required development dependencies for Rails 8.1 compatibility

### Test Results

- [x] All existing tests pass
- [ ] New tests added for new functionality
- [x] Manual testing completed
- [x] Tested across multiple databases (SQLite, PostgreSQL, MySQL)
- [x] Tested across multiple Rails versions (7.2, 8.0, 8.1)
- [x] Tested with Appraisals across all Rails versions

## Breaking Changes

<!-- List any breaking changes and migration steps if applicable -->

- [x] No breaking changes
- [ ] Breaking changes documented below

<!-- If there are breaking changes, describe them and provide migration steps -->
No breaking changes - all changes are backward compatible and maintain existing functionality.

## Screenshots

<!-- If applicable, add screenshots to help explain your changes -->

## Checklist

- [x] Code follows the project's style guidelines
- [x] Self-review of code completed
- [x] Comments added for complex logic
- [x] Documentation updated (if applicable)
- [x] No new warnings or errors introduced
- [x] Tests added/updated and passing
- [x] Changes work with all supported databases
- [x] Changes work with all supported Rails versions (7.2, 8.0, 8.1)
- [x] Appraisals configuration updated if Rails version support changed
- [ ] Asset changes compiled and included (if applicable)

## Additional Notes

<!-- Add any additional context, concerns, or implementation details -->
This PR primarily addresses Rails 8.1 compatibility issues that were preventing the test suite from running. Key technical challenges included:

1. **Missing Dependencies**: Rails 8.1 no longer includes `minitest/mock` by default, requiring explicit addition to gemspec and gemfiles.

2. **Generator Test API Changes**: Rails 8.1 changed the `run_generator` method signature, requiring a new syntax with separate args array and config hash instead of passing arguments directly.

3. **Mocking Framework Updates**: Mocha's mocking syntax needed to be updated from Rails' built-in stub methods to Mocha's `stubs/unstub` pattern.

4. **Documentation Consistency**: All documentation needed updating to reflect the expanded Rails version support matrix.

The changes ensure that Rails Pulse remains fully compatible with Rails 7.2, 8.0, and 8.1, maintaining backward compatibility while adding support for the latest Rails release.

All 443 tests pass across all Rails versions and database configurations.
