#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const esbuild = require('esbuild');

// Configuration
const ENABLE_SOURCE_MAPS = process.env.RAILS_PULSE_SOURCE_MAPS === 'true';
const ROOT_DIR = path.dirname(__dirname);
const OUTPUT_DIR = path.join(ROOT_DIR, 'public', 'rails-pulse-assets');
const JS_DIR = path.join(ROOT_DIR, 'app', 'javascript', 'rails_pulse');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

async function buildJS() {

  try {
    // Use application.js as the entry point
    const entryPath = path.join(JS_DIR, 'application.js');

    // Build with esbuild
    const buildOptions = {
      entryPoints: [entryPath],
      bundle: true,
      outfile: path.join(OUTPUT_DIR, 'rails-pulse.js'),
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

    const result = await esbuild.build(buildOptions);

    // ECharts is now included in the bundle for full asset independence

    const outputPath = path.join(OUTPUT_DIR, 'rails-pulse.js');
    const stats = fs.statSync(outputPath);
    console.log(`✅ JavaScript bundle: ${path.relative(ROOT_DIR, outputPath)} (${(stats.size / 1024).toFixed(1)}KB)`);

    if (ENABLE_SOURCE_MAPS) {
      const mapPath = path.join(OUTPUT_DIR, 'rails-pulse.js.map');
      if (fs.existsSync(mapPath)) {
        console.log(`🗺️  JavaScript source map: ${path.relative(ROOT_DIR, mapPath)}`);
      }
    }

    if (result.warnings.length > 0) {
      console.warn('⚠️  Build warnings:');
      result.warnings.forEach(warning => console.warn(`   ${warning.text}`));
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
