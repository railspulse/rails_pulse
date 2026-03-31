#!/usr/bin/env node

const path = require('path');

// Shared build configuration for Rails Pulse assets
const ROOT_DIR = path.dirname(__dirname);

// Configuration
const ENABLE_SOURCE_MAPS = process.env.RAILS_PULSE_SOURCE_MAPS === 'true';

// Output directories:
// 1. vendor/assets/ - For Sprockets-based apps (gets precompiled into host app)
// 2. public/rails-pulse-assets/ - For middleware fallback (non-Sprockets apps, dev mode)
const OUTPUT_DIRS = [
  {
    name: 'vendor/assets (Sprockets)',
    css: path.join(ROOT_DIR, 'vendor', 'assets', 'stylesheets'),
    js: path.join(ROOT_DIR, 'vendor', 'assets', 'javascripts')
  },
  {
    name: 'public/rails-pulse-assets (Middleware)',
    css: path.join(ROOT_DIR, 'public', 'rails-pulse-assets'),
    js: path.join(ROOT_DIR, 'public', 'rails-pulse-assets')
  }
];

module.exports = {
  ROOT_DIR,
  ENABLE_SOURCE_MAPS,
  OUTPUT_DIRS,
  ASSETS_DIR: path.join(ROOT_DIR, 'app', 'assets', 'stylesheets')
};
