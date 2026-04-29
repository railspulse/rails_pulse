const js = require("@eslint/js")
const globals = require("globals")

module.exports = [
  js.configs.recommended,
  {
    // Third-party files bundled into the project — not our code
    ignores: ["app/javascript/rails_pulse/theme.js"]
  },
  {
    // Stimulus controllers and app JS — ES modules, browser environment
    files: ["app/javascript/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,  // class fields (static values = {}) require 2022+
      sourceType: "module",
      globals: {
        ...globals.browser,
        echarts: "readonly"  // bundled dependency, referenced as global in controllers
      }
    },
    rules: {
      "no-console": ["warn", { allow: ["warn", "error"] }]
    }
  },
  {
    // Build scripts — CommonJS, Node environment
    files: ["scripts/**/*.js"],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: "commonjs",
      globals: {
        ...globals.node
      }
    }
  }
]
