import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import PeriodSelectorController from '../../../app/javascript/rails_pulse/controllers/period_selector_controller'
import { mountController } from '../setup'

const HTML = `
  <div data-controller="period-selector">
    <button data-period-selector-target="button" data-active="true"  style="background: var(--color-primary); color: var(--color-text-reversed)">7d</button>
    <button data-period-selector-target="button" data-active="false" style="background: transparent; color: var(--color-text-subtle)">14d</button>
    <button data-period-selector-target="button" data-active="false" style="background: transparent; color: var(--color-text-subtle)">30d</button>
  </div>
`

describe('PeriodSelectorController', () => {
  let app, element, teardown

  beforeEach(async () => {
    ;({ app, element, teardown } = await mountController('period-selector', PeriodSelectorController, HTML))
  })

  afterEach(() => teardown())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'period-selector')
  }

  function buttons() {
    return [...element.querySelectorAll('[data-period-selector-target="button"]')]
  }

  // # Select

  it('marks the clicked button as active', () => {
    const [, btn14d] = buttons()
    ctrl().select({ currentTarget: btn14d })
    expect(btn14d.dataset.active).toBe('true')
  })

  it('marks all other buttons as inactive', () => {
    const [btn7d, btn14d, btn30d] = buttons()
    ctrl().select({ currentTarget: btn14d })
    expect(btn7d.dataset.active).toBe('false')
    expect(btn30d.dataset.active).toBe('false')
  })

  it('applies active styles to the clicked button', () => {
    const [, btn14d] = buttons()
    ctrl().select({ currentTarget: btn14d })
    expect(btn14d.style.background).toBe('var(--color-primary)')
    expect(btn14d.style.color).toBe('var(--color-text-reversed)')
  })

  it('applies inactive styles to the other buttons', () => {
    const [btn7d, , btn30d] = buttons()
    ctrl().select({ currentTarget: buttons()[1] })
    expect(btn7d.style.background).toBe('transparent')
    expect(btn30d.style.background).toBe('transparent')
  })

  it('handles selecting the already-active button without errors', () => {
    const [btn7d] = buttons()
    expect(() => ctrl().select({ currentTarget: btn7d })).not.toThrow()
    expect(btn7d.dataset.active).toBe('true')
  })
})
