import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import UiModeController from '../../../app/javascript/rails_pulse/controllers/ui_mode_controller'
import { mountController } from '../setup'

const HTML = `
  <div data-controller="ui-mode">
    <button type="button" aria-pressed="false"
            data-ui-mode-target="toggle" data-action="ui-mode#toggle">TUI</button>
  </div>
`

describe('UiModeController', () => {
  let app, element, teardown

  beforeEach(() => {
    localStorage.clear()
    document.documentElement.removeAttribute('data-ui')
  })

  afterEach(() => {
    teardown?.()
    document.documentElement.removeAttribute('data-ui')
  })

  async function mount(initial) {
    if (initial) document.documentElement.setAttribute('data-ui', initial)
    ;({ app, element, teardown } = await mountController('ui-mode', UiModeController, HTML))
    return app.getControllerForElementAndIdentifier(element, 'ui-mode')
  }

  const toggleButton = () => element.querySelector('[data-ui-mode-target="toggle"]')

  // # Connect

  it('marks the button unpressed in the default look', async () => {
    await mount()
    expect(toggleButton().getAttribute('aria-pressed')).toBe('false')
  })

  it('marks the button pressed when TUI was restored by the inline script', async () => {
    await mount('tui')
    expect(toggleButton().getAttribute('aria-pressed')).toBe('true')
  })

  // # Toggle

  it('switches to TUI and saves the mode', async () => {
    const ctrl = await mount()
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.getAttribute('data-ui')).toBe('tui')
    expect(localStorage.getItem('rails-pulse-ui')).toBe('tui')
    expect(toggleButton().getAttribute('aria-pressed')).toBe('true')
  })

  it('switches back to the default look and saves the mode', async () => {
    const ctrl = await mount('tui')
    ctrl.toggle({ preventDefault: vi.fn() })
    expect(document.documentElement.hasAttribute('data-ui')).toBe(false)
    expect(localStorage.getItem('rails-pulse-ui')).toBe('default')
    expect(toggleButton().getAttribute('aria-pressed')).toBe('false')
  })

  it('fires a resize so charts re-measure with the new font', async () => {
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
    expect(document.documentElement.getAttribute('data-ui')).toBe('tui')
  })
})
