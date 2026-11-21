import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import SidebarController from '../../../app/javascript/rails_pulse/controllers/sidebar_controller'
import { mountController } from '../setup'

const HTML = `
  <aside data-controller="sidebar">
    <button type="button" aria-expanded="true" aria-label="Collapse sidebar"
            data-sidebar-target="toggle" data-action="sidebar#toggle">
      <span>Collapse</span>
    </button>
  </aside>
`

describe('SidebarController', () => {
  let app, element, teardown

  beforeEach(() => {
    localStorage.clear()
    document.documentElement.removeAttribute('data-sidebar')
  })

  afterEach(() => {
    teardown?.()
    document.documentElement.removeAttribute('data-sidebar')
  })

  async function mount(initial) {
    if (initial) document.documentElement.setAttribute('data-sidebar', initial)
    ;({ app, element, teardown } = await mountController('sidebar', SidebarController, HTML))
    return app.getControllerForElementAndIdentifier(element, 'sidebar')
  }

  const toggleButton = () => element.querySelector('[data-sidebar-target="toggle"]')

  // # Connect

  it('labels the button for an expanded sidebar by default', async () => {
    await mount()
    expect(toggleButton().getAttribute('aria-expanded')).toBe('true')
    expect(toggleButton().getAttribute('aria-label')).toBe('Collapse sidebar')
    expect(toggleButton().textContent.trim()).toBe('Collapse')
  })

  it('reflects a sidebar already collapsed by the inline script', async () => {
    await mount('collapsed')
    expect(toggleButton().getAttribute('aria-expanded')).toBe('false')
    expect(toggleButton().getAttribute('aria-label')).toBe('Expand sidebar')
    expect(toggleButton().textContent.trim()).toBe('Expand')
  })

  it('restores a collapsed sidebar from storage when the inline script could not run', async () => {
    localStorage.setItem('rails-pulse-sidebar', 'collapsed')
    await mount()
    expect(document.documentElement.getAttribute('data-sidebar')).toBe('collapsed')
    expect(toggleButton().getAttribute('aria-expanded')).toBe('false')
  })

  // # Toggle

  it('collapses an expanded sidebar and saves the state', async () => {
    const ctrl = await mount()
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.getAttribute('data-sidebar')).toBe('collapsed')
    expect(localStorage.getItem('rails-pulse-sidebar')).toBe('collapsed')
  })

  it('expands a collapsed sidebar and saves the state', async () => {
    const ctrl = await mount('collapsed')
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.hasAttribute('data-sidebar')).toBe(false)
    expect(localStorage.getItem('rails-pulse-sidebar')).toBe('expanded')
  })

  it('updates the button after toggling', async () => {
    const ctrl = await mount()
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(toggleButton().getAttribute('aria-expanded')).toBe('false')
    expect(toggleButton().getAttribute('aria-label')).toBe('Expand sidebar')
  })

  it('fires a resize so charts re-measure', async () => {
    const ctrl = await mount()
    const listener = vi.fn()
    window.addEventListener('resize', listener)
    ctrl.toggle({ preventDefault: vi.fn() })
    window.removeEventListener('resize', listener)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  // # Edge Cases

  it('still toggles when storage is unavailable', async () => {
    const ctrl = await mount()
    const spy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('blocked') })
    expect(() => ctrl.toggle({ preventDefault: vi.fn() })).not.toThrow()
    spy.mockRestore()
    expect(document.documentElement.getAttribute('data-sidebar')).toBe('collapsed')
  })
})
