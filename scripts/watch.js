#!/usr/bin/env node

const chokidar = require('chokidar');
const path = require('path');
const { execSync } = require('child_process');

// Configuration
const ROOT_DIR = path.dirname(__dirname);
const CSS_GLOB = path.join(ROOT_DIR, 'app/assets/stylesheets/rails_pulse/**/*.css');
const VENDOR_CSS_GLOB = path.join(ROOT_DIR, 'vendor/css-zero/**/*.css');
const JS_GLOB = path.join(ROOT_DIR, 'app/javascript/rails_pulse/**/*.js');
const VIEW_GLOB = path.join(ROOT_DIR, 'app/views/**/*.{erb,html}');

console.log('🔍 Rails Pulse Asset Watcher Starting...');
console.log('📍 Watching for changes in:');
console.log('   - CSS files: app/assets/stylesheets/rails_pulse/');
console.log('   - Vendor CSS: vendor/css-zero/');
console.log('   - JavaScript: app/javascript/rails_pulse/');
console.log('   - Views (for icons): app/views/');
console.log('');

let buildTimeout;
let isBuilding = false;

function debounce(func, wait) {
  return function(...args) {
    clearTimeout(buildTimeout);
    buildTimeout = setTimeout(() => func.apply(this, args), wait);
  };
}

function runBuild() {
  if (isBuilding) {
    console.log('⏳ Build already in progress, skipping...');
    return;
  }

  isBuilding = true;
  const startTime = Date.now();
  
  try {
    console.log('🔨 Building assets...');
    execSync('RAILS_PULSE_SOURCE_MAPS=true node scripts/build.js', {
      cwd: ROOT_DIR,
      stdio: 'inherit'
    });
    
    const duration = Date.now() - startTime;
    console.log(`✅ Build completed in ${duration}ms`);
    console.log('👀 Watching for changes...\n');
  } catch (error) {
    console.error('❌ Build failed:', error.message);
  } finally {
    isBuilding = false;
  }
}

// Debounced build function (300ms delay)
const debouncedBuild = debounce(runBuild, 300);

// Initialize watcher
const watcher = chokidar.watch([CSS_GLOB, VENDOR_CSS_GLOB, JS_GLOB, VIEW_GLOB], {
  ignored: /(^|[\/\\])\../, // ignore dotfiles
  persistent: true,
  ignoreInitial: true
});

// Set up event handlers
watcher
  .on('change', (filePath) => {
    const relativePath = path.relative(ROOT_DIR, filePath);
    console.log(`📝 Changed: ${relativePath}`);
    debouncedBuild();
  })
  .on('add', (filePath) => {
    const relativePath = path.relative(ROOT_DIR, filePath);
    console.log(`➕ Added: ${relativePath}`);
    debouncedBuild();
  })
  .on('unlink', (filePath) => {
    const relativePath = path.relative(ROOT_DIR, filePath);
    console.log(`➖ Removed: ${relativePath}`);
    debouncedBuild();
  })
  .on('error', (error) => {
    console.error('👀 Watcher error:', error);
  });

// Initial build
console.log('🚀 Running initial build...');
runBuild();

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down watcher...');
  watcher.close().then(() => {
    console.log('✅ Watcher stopped');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('\n🛑 Shutting down watcher...');
  watcher.close().then(() => {
    console.log('✅ Watcher stopped');
    process.exit(0);
  });
});

console.log('👀 Watching for changes... (Press Ctrl+C to stop)');