import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['app/javascript/**/*.test.js'],
    setupFiles: ['app/javascript/test/setup.js'],
  },
})
