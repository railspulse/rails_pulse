#!/usr/bin/env node

const { execSync } = require('child_process');
const path = require('path');

// Configuration
const ENABLE_SOURCE_MAPS = process.env.RAILS_PULSE_SOURCE_MAPS === 'true';
const IS_DEVELOPMENT = ENABLE_SOURCE_MAPS;

console.log('🚀 Building Rails Pulse Assets...');
console.log(`📍 Source Maps: ${ENABLE_SOURCE_MAPS ? 'Enabled' : 'Disabled'}`);
console.log(`🔧 Environment: ${IS_DEVELOPMENT ? 'Development' : 'Production'}`);

// Build steps
const buildSteps = [
  { name: 'CSS Bundle', script: 'build-css.js' },
  { name: 'JavaScript Bundle', script: 'build-js.js' },
  { name: 'Icons Bundle', script: 'build-icons.js' }
];

// Execute each build step
for (const step of buildSteps) {
  try {
    console.log(`\n📦 Building ${step.name}...`);

    const env = {
      ...process.env,
      RAILS_PULSE_SOURCE_MAPS: ENABLE_SOURCE_MAPS.toString()
    };

    execSync(`node "${path.join(__dirname, step.script)}"`, {
      stdio: 'inherit',
      env,
      cwd: path.dirname(__dirname)
    });

    console.log(`✅ ${step.name} completed successfully`);
  } catch (error) {
    console.error(`❌ Failed to build ${step.name}:`, error.message);
    process.exit(1);
  }
}

console.log('\n🎉 All assets built successfully!');
console.log('📂 Assets available at: public/rails-pulse-assets/');

if (ENABLE_SOURCE_MAPS) {
  console.log('🗺️  Source maps generated for development debugging');
}

console.log('\n📋 Generated files:');
console.log('  - rails-pulse.css');
console.log('  - rails-pulse.js');
console.log('  - rails-pulse-icons.js');

if (ENABLE_SOURCE_MAPS) {
  console.log('  - rails-pulse.css.map');
  console.log('  - rails-pulse.js.map');
}
