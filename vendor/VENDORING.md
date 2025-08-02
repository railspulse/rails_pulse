# CSS Zero Vendoring Documentation

This document describes the process for vendoring CSS Zero dependencies for Rails Pulse asset independence.

## Overview

Rails Pulse vendors CSS Zero files to eliminate external gem dependencies during asset compilation. This ensures the build system can function independently without requiring the `css-zero` gem to be installed.

## Current CSS Zero Version

**Vendored Version**: 1.1.5  
**Vendored Date**: 2025-07-02  
**Source**: `css-zero` gem (https://github.com/lazaronixon/css-zero)

## Directory Structure

```
vendor/css-zero/
├── reset.css           # CSS reset and base styles
├── colors.css          # Color variables and utilities
├── sizes.css           # Size and spacing variables
├── borders.css         # Border variables and utilities
├── effects.css         # Shadow and effect variables
├── typography.css      # Font and text variables
├── animations.css      # Animation keyframes and utilities
├── transforms.css      # Transform utilities
├── transitions.css     # Transition utilities
├── filters.css         # Filter utilities
├── utilities.css       # All utility classes
└── variables.css       # Master import file (not used in build)
```

## Build Integration

The CSS build system (`scripts/build-css.js`) includes CSS Zero files in this order:

1. **CSS Zero Reset** (`reset.css`)
2. **CSS Zero Variables** (9 component files):
   - `colors.css`
   - `sizes.css`
   - `borders.css`
   - `effects.css`
   - `typography.css`
   - `animations.css`
   - `transforms.css`
   - `transitions.css`
   - `filters.css`
3. **Rails Pulse Components** (all files in `app/assets/stylesheets/rails_pulse/components/`)
4. **Rails Pulse Application CSS** (`app/assets/stylesheets/rails_pulse/application.css`)
5. **CSS Zero Utilities** (`utilities.css`)

## Updating CSS Zero

To update the vendored CSS Zero files:

### 1. Update CSS Zero Gem

```bash
# Update Gemfile or gemspec with new version
bundle update css-zero
```

### 2. Find New CSS Zero Path

```bash
bundle show css-zero
# Example output: /path/to/gems/css-zero-X.Y.Z
```

### 3. Copy New Files

```bash
# Remove old vendored files
rm -rf vendor/css-zero

# Create directory
mkdir -p vendor/css-zero

# Copy new CSS files
cp /path/to/gems/css-zero-X.Y.Z/app/assets/stylesheets/css-zero/*.css vendor/css-zero/
```

### 4. Verify File Structure

Ensure these files exist:
- `reset.css`
- `colors.css`
- `sizes.css`
- `borders.css`
- `effects.css`
- `typography.css`
- `animations.css`
- `transforms.css`
- `transitions.css`
- `filters.css`
- `utilities.css`
- `variables.css` (not used in build, but included for completeness)

### 5. Test Build System

```bash
# Test CSS build
npm run build:css

# Test complete build
npm run build

# Verify bundle size and content
ls -la public/rails-pulse-assets/rails-pulse.css
```

### 6. Update Documentation

- Update version number in this file
- Update vendored date
- Note any breaking changes or new features
- Update ASSET_PIPELINE.md if build order changes

## Verification Checklist

After updating CSS Zero:

- [ ] All CSS files copied successfully
- [ ] Build system completes without errors
- [ ] CSS bundle includes all expected utilities
- [ ] Rails Pulse styling works correctly
- [ ] No missing CSS variables or utilities
- [ ] Bundle size is reasonable (typically 50-60KB)

## Breaking Changes

When updating CSS Zero, watch for:

- **Removed utilities**: Check if any CSS classes used by Rails Pulse were removed
- **Variable changes**: Ensure CSS custom properties haven't changed names
- **File structure changes**: Verify all expected CSS files are still present
- **Import dependencies**: Check if new files need to be added to the build order

## Support

If you encounter issues with vendored CSS Zero:

1. Check the CSS Zero repository for changelog: https://github.com/lazaronixon/css-zero
2. Verify all files are properly copied and accessible
3. Test the build system with a clean npm run build
4. Compare bundle size and content with previous versions

## License

CSS Zero is licensed under the MIT License. The vendored files retain their original license headers.