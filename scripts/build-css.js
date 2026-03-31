#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const postcss = require('postcss');
const autoprefixer = require('autoprefixer');
const cssnano = require('cssnano');
const { glob } = require('glob');
const { ROOT_DIR, ENABLE_SOURCE_MAPS, OUTPUT_DIRS, ASSETS_DIR } = require('./build-config');

// Ensure all output directories exist
OUTPUT_DIRS.forEach(output => {
  if (!fs.existsSync(output.css)) {
    fs.mkdirSync(output.css, { recursive: true });
  }
});

async function buildCSS() {

  try {
    // CSS bundling order (as per ASSET_PIPELINE.md)
    const cssOrder = [
      // CSS Zero Reset
      'vendor/css-zero/reset.css',
      // CSS Zero Variables (9 component files)
      'vendor/css-zero/colors.css',
      'vendor/css-zero/sizes.css',
      'vendor/css-zero/borders.css',
      'vendor/css-zero/effects.css',
      'vendor/css-zero/typography.css',
      'vendor/css-zero/animations.css',
      'vendor/css-zero/transforms.css',
      'vendor/css-zero/transitions.css',
      'vendor/css-zero/filters.css',
      // Flatpickr CSS
      'vendor/flatpickr.css',
      // Rails Pulse Components
      ...glob.sync(path.join(ASSETS_DIR, 'rails_pulse/components/*.css')).sort(),
      // Rails Pulse Application CSS
      path.join(ASSETS_DIR, 'rails_pulse/application.css'),
      // CSS Zero Utilities
      'vendor/css-zero/utilities.css'
    ];

    // Collect CSS content
    let cssContent = '';
    const sourceMapSources = [];

    for (const cssFile of cssOrder) {
      const fullPath = path.isAbsolute(cssFile) ? cssFile : path.join(ROOT_DIR, cssFile);
      
      if (fs.existsSync(fullPath)) {
        const content = fs.readFileSync(fullPath, 'utf8');
        cssContent += `\n/* ${path.relative(ROOT_DIR, fullPath)} */\n${content}\n`;
        sourceMapSources.push(path.relative(ROOT_DIR, fullPath));
      } else {
        console.warn(`⚠️  CSS file not found: ${fullPath}`);
      }
    }

    // Process with PostCSS
    const postcssPlugins = [
      autoprefixer()
    ];

    // Add minification in production
    if (!ENABLE_SOURCE_MAPS) {
      postcssPlugins.push(cssnano({
        preset: 'default'
      }));
    }

    const result = await postcss(postcssPlugins).process(cssContent, {
      from: 'rails-pulse.css',
      to: 'rails-pulse.css',
      map: ENABLE_SOURCE_MAPS ? {
        inline: false,
        sourcesContent: true
      } : false
    });

    // Write CSS file to all output directories
    OUTPUT_DIRS.forEach(output => {
      const outputPath = path.join(output.css, 'rails-pulse.css');
      fs.writeFileSync(outputPath, result.css);

      // Write source map if enabled
      if (ENABLE_SOURCE_MAPS && result.map) {
        const mapPath = path.join(output.css, 'rails-pulse.css.map');
        fs.writeFileSync(mapPath, result.map.toString());
      }

      const stats = fs.statSync(outputPath);
      console.log(`✅ CSS → ${output.name}: ${path.relative(ROOT_DIR, outputPath)} (${(stats.size / 1024).toFixed(1)}KB)`);
    });

  } catch (error) {
    console.error('❌ CSS build failed:', error);
    throw error;
  }
}

// Run if called directly
if (require.main === module) {
  buildCSS().catch((error) => {
    console.error('CSS build failed:', error);
    process.exit(1);
  });
}

module.exports = buildCSS;