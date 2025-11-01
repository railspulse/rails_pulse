## Summary

Replace rails_charts gem dependency with direct Apache ECharts implementation. This removes the intermediate gem wrapper and implements chart rendering directly in RailsPulse, maintaining full CSP compliance and all existing functionality.

## Type of Change

<!-- Mark the relevant option with an [x] -->

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Performance improvement
- [x] Code refactoring (no functional changes)
- [x] Documentation update
- [ ] Test improvements
- [ ] Build/CI improvements

## Changes Made

### Core Implementation
- Implemented `rails_pulse_bar_chart` helper method in `ChartHelper` with direct eCharts integration
- Added CSP-compliant chart rendering with nonce-based inline script injection
- Implemented async eCharts loading with retry mechanism to handle load timing
- Added JavaScript function wrapper system (`js_function`) for safe JSON serialization
- Maintained `window.RailsPulse.charts` global registry for Stimulus controller integration

### Chart Data Flow
- Renamed `to_rails_chart` method to `to_chart_data` in all chart model classes (4 files)
- Updated chart concern to use new method name

### Dependency Removal
- Removed rails_charts gem from gemspec and all Gemfiles (4 files)
- Removed `require "rails_charts"` from engine.rb
- Deleted rails_charts CSP patch initializer
- Removed rails_charts configuration code from engine.rb
- Regenerated all Gemfile.lock files

### View Updates
- Updated 8 view files to use `rails_pulse_bar_chart` instead of `bar_chart`
- Updated JavaScript controller to reference `window.RailsPulse` instead of `window.RailsCharts`

### Documentation & Comments
- Updated README.md to reference Apache ECharts directly
- Removed rails_charts mentions from comments and documentation
- Updated CSP test page descriptions

### Test Updates
- Updated test helpers to expect new function wrapper format
- Updated system test helpers to use `window.RailsPulse` namespace
- All chart-related tests passing

### Test Results

- [x] All existing tests pass (274 runs, 834 assertions)
- [ ] New tests added for new functionality
- [x] Manual testing completed
- [x] Tested across multiple databases (SQLite, PostgreSQL, MySQL)
- [ ] Tested across multiple Rails versions (7.2, 8.0)

## Breaking Changes

<!-- List any breaking changes and migration steps if applicable -->

- [ ] No breaking changes
- [ ] Breaking changes documented below

<!-- If there are breaking changes, describe them and provide migration steps -->

## Screenshots

<!-- If applicable, add screenshots to help explain your changes -->

## Checklist

- [ ] Code follows the project's style guidelines
- [ ] Self-review of code completed
- [ ] Comments added for complex logic
- [ ] Documentation updated (if applicable)
- [ ] No new warnings or errors introduced
- [ ] Tests added/updated and passing
- [ ] Changes work with all supported databases
- [ ] Changes work with all supported Rails versions
- [ ] Asset changes compiled and included (if applicable)

## Additional Notes

<!-- Add any additional context, concerns, or implementation details -->
