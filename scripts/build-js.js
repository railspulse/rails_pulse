#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const esbuild = require('esbuild');
const { ROOT_DIR, ENABLE_SOURCE_MAPS, OUTPUT_DIRS } = require('./build-config');

// Configuration
const VERBOSE = process.env.RAILS_PULSE_VERBOSE === 'true';
const JS_DIR = path.join(ROOT_DIR, 'app', 'javascript', 'rails_pulse');

// Ensure all output directories exist
OUTPUT_DIRS.forEach(output => {
  if (!fs.existsSync(output.js)) {
    fs.mkdirSync(output.js, { recursive: true });
  }
});

async function buildJS() {

  try {
    // Use application.js as the entry point
    const entryPath = path.join(JS_DIR, 'application.js');

    // Build options shared for all outputs
    const baseBuildOptions = {
      entryPoints: [entryPath],
      bundle: true,
      format: 'iife',
      target: 'es2020',
      minify: !ENABLE_SOURCE_MAPS,
      sourcemap: ENABLE_SOURCE_MAPS,
      define: {
        'process.env.NODE_ENV': ENABLE_SOURCE_MAPS ? '"development"' : '"production"'
      },
      external: [],
      banner: {
        js: '// Rails Pulse JavaScript Bundle - Auto-generated'
      }
    };

    // Build to each output directory
    for (const output of OUTPUT_DIRS) {
      const outfile = path.join(output.js, 'rails-pulse.js');

      const result = await esbuild.build({
        ...baseBuildOptions,
        outfile
      });

      const stats = fs.statSync(outfile);
      console.log(`✅ JS → ${output.name}: ${path.relative(ROOT_DIR, outfile)} (${(stats.size / 1024).toFixed(1)}KB)`);

      if (ENABLE_SOURCE_MAPS) {
        const mapPath = path.join(output.js, 'rails-pulse.js.map');
        if (fs.existsSync(mapPath)) {
          if (VERBOSE) {
            console.log(`🗺️  JS source map: ${path.relative(ROOT_DIR, mapPath)}`);
          }
        }
      }

      if (VERBOSE && result.warnings.length > 0) {
        console.warn('⚠️  Build warnings:');
        result.warnings.forEach(warning => console.warn(`   ${warning.text}`));
      }
    }

  } catch (error) {
    console.error('❌ JavaScript build failed:', error);
    throw error;
  }
}

// Run if called directly
if (require.main === module) {
  buildJS().catch((error) => {
    console.error('JavaScript build failed:', error);
    process.exit(1);
  });
}

module.exports = buildJS;
