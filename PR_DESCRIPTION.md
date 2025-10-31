## Summary

Add support for both Pagy 8.x and Pagy 43 (pre-release of 9.x), ensuring backward compatibility with existing installations while allowing users to adopt the latest Pagy version. This builds on PR #53 by @kylekeesling and adds a comprehensive compatibility layer.

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [x] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Performance improvement
- [x] Code refactoring (no functional changes)
- [ ] Documentation update
- [x] Test improvements
- [ ] Build/CI improvements

## Changes Made

### Controller Changes
- Added conditional include in `ApplicationController` to support both `Pagy::Method` (9+) and `Pagy::Backend` (8.x)
- Changed all `pagy()` calls from `limit:` to `items:` parameter (works in both versions)
- Kept existing session-based pagination limit functionality

### Helper Changes
- Added `Pagy::Frontend` include for Pagy 8.x compatibility
- Added compatibility helper methods:
  - `pagy_items(pagy)` - Gets items per page from either API version
  - `pagy_page_url(pagy, page_number)` - Generates page URLs for both versions
  - `pagy_previous(pagy)` - Gets previous page (handles `prev` vs `previous`)
  - `pagy_next(pagy)` - Gets next page number
- Updated `_table_pagination.html.erb` to use compatibility helpers instead of direct Pagy calls

### JavaScript Changes
- Updated `pagination_controller.js` to use `Turbo.visit()` for proper URL parameter handling
- Fixed pagination dropdown to sync with URL parameters (URL params take precedence over sessionStorage)
- Removed unused methods (`getCSRFToken`, `savePaginationLimit`, `url` value)
- Cleaned up and simplified code

### Gem Dependencies
- Updated `Gemfile` and `rails_pulse.gemspec` to support `pagy >= 8, < 44`
- Updated Appraisals to test both versions:
  - Rails 7.2 with Pagy 8.6 (tests `Pagy::Backend` API)
  - Rails 8.0 with Pagy 43 (tests `Pagy::Method` API)

### Bug Fixes
- Fixed pagination dropdown not updating table row count
- Fixed pagination not respecting URL parameters on page refresh
- Fixed sessionStorage overriding URL parameters

### Test Results

- [x] All existing tests pass
- [ ] New tests added for new functionality
- [x] Manual testing completed
- [x] Tested across multiple databases (SQLite, PostgreSQL, MySQL)
- [x] Tested across multiple Rails versions (7.2, 8.0)

## Breaking Changes

- [x] No breaking changes
- [ ] Breaking changes documented below

## Checklist

- [x] Code follows the project's style guidelines
- [x] Self-review of code completed
- [x] Comments added for complex logic
- [ ] Documentation updated (if applicable)
- [x] No new warnings or errors introduced
- [x] Tests added/updated and passing
- [x] Changes work with all supported databases
- [x] Changes work with all supported Rails versions
- [x] Asset changes compiled and included (if applicable)

## Additional Notes

### Backward Compatibility

This PR ensures full backward compatibility with Pagy 8.x (which most users likely have installed) while also supporting the new Pagy 43 API. The compatibility layer:

1. **Automatically detects** which Pagy version is installed
2. **Uses the appropriate API** for that version
3. **Requires no changes** from end users

### Testing Strategy

The Appraisals setup tests both Pagy versions in the CI matrix:
- **Rails 7.2 + Pagy 8.6** - Tests the `Pagy::Backend` API path
- **Rails 8.0 + Pagy 43** - Tests the `Pagy::Method` API path

This ensures both code paths are validated on every CI run.

### Credits

- Original Pagy 43 support by @kylekeesling in PR #53
- Pagy 8.x compatibility layer added by @scottharvey
