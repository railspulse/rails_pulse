#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { glob } = require('glob');

// Configuration
const ENABLE_SOURCE_MAPS = process.env.RAILS_PULSE_SOURCE_MAPS === 'true';
const ROOT_DIR = path.dirname(__dirname);
const OUTPUT_DIR = path.join(ROOT_DIR, 'public', 'rails-pulse-assets');
const VIEWS_DIR = path.join(ROOT_DIR, 'app', 'views');

// Icons used by Rails Pulse (from analysis of views)
const REQUIRED_ICONS = [
  'menu',
  'sun',
  'moon',
  'chevron-right',
  'chevron-left',
  'chevron-down',
  'chevron-up',
  'chevrons-left',
  'chevrons-right',
  'loader-circle',
  'search',
  'list-filter',
  'list-filter-plus',
  'x',
  'x-circle',
  'check',
  'alert-circle',
  'alert-triangle',
  'info',
  'external-link',
  'download',
  'refresh-cw',
  'clock',
  'database',
  'server',
  'activity',
  'layout-dashboard',
  'audio-lines',
  'message-circle-question',
  'route',
  'trending-up',
  'trending-down',
  'move-right',
  'eye',
  'zap'
];

// Icon name mappings for different naming conventions
const ICON_MAPPINGS = {
  'loader-circle': 'loader',
  'triangle-alert': 'alert-triangle',
  'alert-circle': 'circle-alert',
  'alert-triangle': 'triangle-alert',
  'x-circle': 'circle-x',
  'filter': 'list-filter',
  'message-circle-question': 'message-circle-question-mark',
  'trending-#{trend_direction}': null // This is dynamic ERB, skip it
};

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

function extractSVGContent(iconName) {
  try {
    // Check if icon name needs mapping or should be skipped
    const mappedName = ICON_MAPPINGS[iconName];
    if (mappedName === null) {
      console.warn(`⚠️  Icon '${iconName}' is dynamic/templated, skipping`);
      return `<rect width="20" height="20" fill="currentColor" opacity="0.3"/>`;
    }

    const actualIconName = mappedName || iconName;

    // Try to get SVG from lucide package (ESM format)
    const lucideIconPath = path.join(ROOT_DIR, 'node_modules', 'lucide', 'dist', 'esm', 'icons', `${actualIconName}.js`);

    if (fs.existsSync(lucideIconPath)) {
      const iconContent = fs.readFileSync(lucideIconPath, 'utf8');

      // Parse the JavaScript array format from Lucide
      // Old format: const Menu = ["svg", defaultAttributes, [["line", { x1: "4", x2: "20", y1: "12", y2: "12" }]]]
      // New format: const ListFilter = [["path", { d: "M2 5h20" }], ["path", { d: "M6 12h12" }]]
      const match = iconContent.match(/const\s+\w+\s*=\s*(\[[\s\S]+?\]);[\s\S]*export/);
      if (!match) {
        throw new Error(`Could not parse icon array from ${iconName}.js`);
      }

      try {
        // Safely evaluate the array (it's just a static data structure)
        const iconArray = eval(match[1]);

        if (Array.isArray(iconArray)) {
          // New format (v0.545+): icon data is directly the elements array
          // Check if first element is ["svg", ...] (old format) or ["path"/"circle"/etc, ...] (new format)
          const isOldFormat = iconArray.length >= 3 && iconArray[0] === 'svg';
          const elements = isOldFormat ? iconArray[2] : iconArray;
          return convertArrayToSVG(elements);
        }
      } catch (evalError) {
        console.warn(`⚠️  Could not evaluate icon array for ${iconName}:`, evalError.message);
      }
    }

    // Fallback: create a simple placeholder
    console.warn(`⚠️  Icon not found: ${iconName}, using placeholder`);
    return `<rect width="20" height="20" fill="currentColor" opacity="0.3"/>`;

  } catch (error) {
    console.warn(`⚠️  Error loading icon ${iconName}:`, error.message);
    return `<rect width="20" height="20" fill="currentColor" opacity="0.3"/>`;
  }
}

function convertArrayToSVG(elements) {
  if (!Array.isArray(elements)) return '';

  return elements.map(element => {
    if (!Array.isArray(element) || element.length < 2) return '';

    const [tagName, attributes, children] = element;
    let svg = `<${tagName}`;

    // Add attributes
    if (attributes && typeof attributes === 'object') {
      for (const [key, value] of Object.entries(attributes)) {
        svg += ` ${key}="${value}"`;
      }
    }

    if (children && Array.isArray(children) && children.length > 0) {
      svg += `>${convertArrayToSVG(children)}</${tagName}>`;
    } else {
      svg += ' />';
    }

    return svg;
  }).join('');
}

async function buildIcons() {

  try {
    // Scan views to find used icons (for verification)
    const viewFiles = glob.sync(path.join(VIEWS_DIR, '**/*.html.erb'));
    const usedIcons = new Set();

    for (const viewFile of viewFiles) {
      const content = fs.readFileSync(viewFile, 'utf8');
      const iconMatches = content.match(/lucide_icon\s+['"]([^'"]+)['"]/g);

      if (iconMatches) {
        iconMatches.forEach(match => {
          const iconName = match.match(/lucide_icon\s+['"]([^'"]+)['"]/)[1];
          usedIcons.add(iconName);
        });
      }
    }

    console.log(`📋 Found ${usedIcons.size} icons in views:`, Array.from(usedIcons).sort());

    // Combine found icons with required icons
    const allIcons = new Set([...REQUIRED_ICONS, ...usedIcons]);

    // Build icon bundle
    const iconBundle = {};

    for (const iconName of allIcons) {
      iconBundle[iconName] = extractSVGContent(iconName);
    }

    // Create JavaScript bundle
    const jsContent = `// Rails Pulse Icons Bundle - Auto-generated
// Contains ${Object.keys(iconBundle).length} SVG icons for Rails Pulse

(function() {
  'use strict';

  // Icon data
  const icons = ${JSON.stringify(iconBundle, null, 2)};

  // Global icon registry
  window.RailsPulseIcons = {
    icons: icons,

    // Get icon SVG content
    get: function(name) {
      return icons[name] || null;
    },

    // Check if icon exists
    has: function(name) {
      return name in icons;
    },

    // Get all icon names
    list: function() {
      return Object.keys(icons);
    },

    // Render icon to element (CSP-safe)
    render: function(name, element, options = {}) {
      const svgContent = this.get(name);
      if (!svgContent || !element) return false;

      // Create SVG element
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('width', options.width || '24');
      svg.setAttribute('height', options.height || '24');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('fill', 'none');
      svg.setAttribute('stroke', 'currentColor');
      svg.setAttribute('stroke-width', '2');
      svg.setAttribute('stroke-linecap', 'round');
      svg.setAttribute('stroke-linejoin', 'round');

      // Add icon content
      svg.innerHTML = svgContent;

      // Replace element content
      element.innerHTML = '';
      element.appendChild(svg);

      return true;
    }
  };
})();
`;

    // Write icons bundle
    const outputPath = path.join(OUTPUT_DIR, 'rails-pulse-icons.js');
    fs.writeFileSync(outputPath, jsContent);

    const stats = fs.statSync(outputPath);
    console.log(`✅ Icons bundle: ${path.relative(ROOT_DIR, outputPath)} (${(stats.size / 1024).toFixed(1)}KB)`);
    console.log(`📦 Bundled ${Object.keys(iconBundle).length} icons:`, Object.keys(iconBundle).sort().join(', '));

    // Generate source map if enabled
    if (ENABLE_SOURCE_MAPS) {
      const sourceMap = {
        version: 3,
        file: 'rails-pulse-icons.js',
        sourceRoot: '',
        sources: ['rails-pulse-icons.js'],
        names: [],
        mappings: '',
        sourcesContent: [jsContent]
      };

      const mapPath = path.join(OUTPUT_DIR, 'rails-pulse-icons.js.map');
      fs.writeFileSync(mapPath, JSON.stringify(sourceMap, null, 2));
      console.log(`🗺️  Icons source map: ${path.relative(ROOT_DIR, mapPath)}`);
    }

  } catch (error) {
    console.error('❌ Icons build failed:', error);
    throw error;
  }
}

// Run if called directly
if (require.main === module) {
  buildIcons().catch((error) => {
    console.error('Icons build failed:', error);
    process.exit(1);
  });
}

module.exports = buildIcons;
