#!/usr/bin/env node

const chokidar = require('chokidar');
const path = require('path');
const { execSync } = require('child_process');

// Configuration
const ROOT_DIR = path.dirname(__dirname);
// Watch directories instead of individual files to handle Vim's safe-write behavior
const WATCH_PATHS = [
  'app/assets/stylesheets/rails_pulse',
  'vendor/css-zero',
  'app/javascript/rails_pulse',
  'app/views'
];

console.log('🔍 Rails Pulse Asset Watcher Starting...');
console.log('📍 Watching directories:');
WATCH_PATHS.forEach(dir => console.log(`   - ${dir}`));
console.log('');

let buildTimeout;
let isBuilding = false;
let buildAbortController = null;

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
  buildAbortController = new AbortController();
  const startTime = Date.now();
  
  try {
    console.log('🔨 Building assets...');
    execSync('RAILS_PULSE_SOURCE_MAPS=true node scripts/build.js', {
      cwd: ROOT_DIR,
      stdio: 'inherit',
      signal: buildAbortController.signal
    });
    
    const duration = Date.now() - startTime;
    console.log(`✅ Build completed in ${duration}ms`);
    console.log('👀 Watching for changes...\n');
  } catch (error) {
    if (error.name === 'AbortError') {
      console.log('⚠️  Build was cancelled');
    } else {
      console.error('❌ Build failed:', error.message);
      console.log('🔄 Will retry on next file change...');
    }
  } finally {
    isBuilding = false;
    buildAbortController = null;
  }
}

// Debounced build function (500ms delay for better stability)
const debouncedBuild = debounce(runBuild, 500);

// Initialize watcher with directory paths to handle Vim's safe-write behavior
const watcher = chokidar.watch(WATCH_PATHS, {
  ignored: /(^|[/\\])\../, // ignore dotfiles
  persistent: true,
  ignoreInitial: true,
  usePolling: false,
  atomic: 300, // Wait 300ms for atomic writes to complete
  awaitWriteFinish: {
    stabilityThreshold: 200,
    pollInterval: 100
  },
  cwd: ROOT_DIR
});

// Helper function to check if file should trigger a build
function shouldBuildForFile(filePath) {
  const ext = path.extname(filePath);
  const validExts = ['.css', '.js', '.erb', '.html'];
  return validExts.includes(ext);
}

// Set up event handlers
watcher
  .on('change', (filePath) => {
    if (!shouldBuildForFile(filePath)) return;
    const relativePath = path.relative(ROOT_DIR, filePath);
    console.log(`📝 Changed: ${relativePath}`);
    debouncedBuild();
  })
  .on('add', (filePath) => {
    if (!shouldBuildForFile(filePath)) return;
    const relativePath = path.relative(ROOT_DIR, filePath);
    console.log(`➕ Added: ${relativePath}`);
    debouncedBuild();
  })
  .on('unlink', (filePath) => {
    if (!shouldBuildForFile(filePath)) return;
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
function shutdown() {
  console.log('\n🛑 Shutting down watcher...');
  
  // Cancel any ongoing build
  if (buildAbortController) {
    buildAbortController.abort();
  }
  
  // Clear any pending timeouts
  if (buildTimeout) {
    clearTimeout(buildTimeout);
  }
  
  watcher.close().then(() => {
    console.log('✅ Watcher stopped');
    process.exit(0);
  }).catch((error) => {
    console.error('❌ Error during shutdown:', error.message);
    process.exit(1);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught exception:', error.message);
  shutdown();
});
process.on('unhandledRejection', (reason) => {
  console.error('❌ Unhandled rejection:', reason);
  shutdown();
});

console.log('👀 Watching for changes... (Press Ctrl+C to stop)');
