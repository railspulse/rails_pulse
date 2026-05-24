const js = require("@eslint/js")
const globals = require("globals")
const vitest = require("@vitest/eslint-plugin")

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
    // Test files — vitest plugin handles globals and adds test-specific rules
    files: ["test/javascript/**/*.test.js", "test/javascript/**/*.js"],
    plugins: { vitest },
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...vitest.environments.env.globals,
      }
    },
    rules: {
      ...vitest.configs.recommended.rules,
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
