import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import ColorSchemeController from '../../../app/javascript/rails_pulse/controllers/color_scheme_controller'
import { mountController } from '../setup'

const HTML = `<div data-controller="color-scheme"></div>`

describe('ColorSchemeController', () => {
  let app, element, teardown

  beforeEach(() => {
    localStorage.clear()
    document.documentElement.removeAttribute('data-color-scheme')
  })

  afterEach(() => teardown?.())

  async function mount(initialScheme) {
    if (initialScheme) document.documentElement.setAttribute('data-color-scheme', initialScheme)
    ;({ app, element, teardown } = await mountController('color-scheme', ColorSchemeController, HTML))
    return app.getControllerForElementAndIdentifier(element, 'color-scheme')
  }

  // # Connect

  it('restores a saved scheme from localStorage on connect', async () => {
    localStorage.setItem('color-scheme', 'dark')
    await mount()
    expect(document.documentElement.getAttribute('data-color-scheme')).toBe('dark')
  })

  it('does not alter scheme when nothing is saved', async () => {
    await mount()
    expect(document.documentElement.hasAttribute('data-color-scheme')).toBe(false)
  })

  // # Toggle

  it('switches from light to dark', async () => {
    const ctrl = await mount('light')
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.getAttribute('data-color-scheme')).toBe('dark')
  })

  it('switches from dark to light', async () => {
    const ctrl = await mount('dark')
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.getAttribute('data-color-scheme')).toBe('light')
  })

  it('persists the new scheme to localStorage', async () => {
    const ctrl = await mount('light')
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(localStorage.getItem('color-scheme')).toBe('dark')
  })

  it('dispatches rails-pulse:color-scheme-changed with the new scheme', async () => {
    const ctrl = await mount('light')
    const received = []
    document.addEventListener('rails-pulse:color-scheme-changed', e => received.push(e.detail))
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(received).toHaveLength(1)
    expect(received[0]).toEqual({ scheme: 'dark' })
  })
})
