import { describe, it, expect, afterEach, vi } from 'vitest'
import GlobalFiltersController from './global_filters_controller'
import { mountController } from '../../test/setup'

function buildHTML({ active = false } = {}) {
  return `
    <div data-controller="global-filters"
         data-global-filters-active-value="${active}">
      <div data-global-filters-target="wrapper" style="display: none"></div>
      <div data-global-filters-target="indicator"></div>
      <form data-global-filters-target="form"></form>
    </div>
  `
}

describe('GlobalFiltersController', () => {
  let app, element, teardown

  afterEach(() => {
    teardown?.()
    document.body.style.overflow = ''
  })

  async function mount(options = {}) {
    ;({ app, element, teardown } = await mountController('global-filters', GlobalFiltersController, buildHTML(options)))
    return app.getControllerForElementAndIdentifier(element, 'global-filters')
  }

  function wrapper() { return element.querySelector('[data-global-filters-target="wrapper"]') }
  function indicator() { return element.querySelector('[data-global-filters-target="indicator"]') }

  // # Indicator on connect

  it('adds active class to indicator when active=true', async () => {
    await mount({ active: true })
    expect(indicator().classList.contains('global-filters-active')).toBe(true)
  })

  it('does not add active class when active=false', async () => {
    await mount({ active: false })
    expect(indicator().classList.contains('global-filters-active')).toBe(false)
  })

  // # open

  it('shows the wrapper as flex', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    expect(wrapper().style.display).toBe('flex')
  })

  it('locks body scroll', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    expect(document.body.style.overflow).toBe('hidden')
  })

  it('prevents default on the event', async () => {
    const ctrl = await mount()
    const preventDefault = vi.fn()
    ctrl.open({ preventDefault })
    expect(preventDefault).toHaveBeenCalledOnce()
  })

  // # close

  it('hides the wrapper', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    ctrl.close({ preventDefault: vi.fn() })
    expect(wrapper().style.display).toBe('none')
  })

  it('restores body scroll', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    ctrl.close({ preventDefault: vi.fn() })
    expect(document.body.style.overflow).toBe('')
  })

  it('close works without an event argument', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    expect(() => ctrl.close()).not.toThrow()
    expect(wrapper().style.display).toBe('none')
  })

  // # closeOnClickOutside

  it('closes when click target is the wrapper', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    ctrl.closeOnClickOutside({ target: wrapper(), preventDefault: vi.fn() })
    expect(wrapper().style.display).toBe('none')
  })

  it('does not close when click target is inside the wrapper', async () => {
    const ctrl = await mount()
    ctrl.open({ preventDefault: vi.fn() })
    ctrl.closeOnClickOutside({ target: indicator(), preventDefault: vi.fn() })
    expect(wrapper().style.display).toBe('flex')
  })

  // # activeValueChanged

  it('adds active class when activeValue is set to true', async () => {
    const ctrl = await mount({ active: false })
    ctrl.activeValue = true
    ctrl.activeValueChanged()
    expect(indicator().classList.contains('global-filters-active')).toBe(true)
  })

  it('removes active class when activeValue is set to false', async () => {
    const ctrl = await mount({ active: true })
    ctrl.activeValue = false
    ctrl.activeValueChanged()
    expect(indicator().classList.contains('global-filters-active')).toBe(false)
  })
})
