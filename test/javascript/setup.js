import { vi } from 'vitest'
import { Application } from '@hotwired/stimulus'

// Polyfill browser APIs not implemented in JSDOM
globalThis.IntersectionObserver = vi.fn(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}))

globalThis.ResizeObserver = vi.fn(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}))

// Wait for Stimulus MutationObserver to process DOM changes
export const nextTick = () => new Promise(resolve => setTimeout(resolve, 0))

// Mount a single controller in a fresh Stimulus app.
// Returns { app, element } and sets document.body.innerHTML to the given HTML.
// Call teardown() in afterEach to stop the app and reset the DOM.
export async function mountController(identifier, ControllerClass, html) {
  document.body.innerHTML = html
  const app = Application.start()
  app.register(identifier, ControllerClass)
  await nextTick()
  return {
    app,
    element: document.querySelector(`[data-controller="${identifier}"]`),
    teardown() {
      app.stop()
      document.body.innerHTML = ''
    },
  }
}
