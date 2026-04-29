import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import CollapsibleController from './collapsible_controller'
import { mountController } from '../../test/setup'

// Uses "is-collapsed" as the class name, passed via Stimulus class API attribute.
const HTML = `
  <div data-controller="collapsible"
       data-collapsible-collapsed-class="is-collapsed">
    <div data-collapsible-target="content">content</div>
    <button data-collapsible-target="toggle">toggle</button>
  </div>
`

describe('CollapsibleController', () => {
  let app, element, teardown

  beforeEach(async () => {
    ;({ app, element, teardown } = await mountController('collapsible', CollapsibleController, HTML))
  })

  afterEach(() => teardown())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'collapsible')
  }

  function toggleBtn() {
    return element.querySelector('[data-collapsible-target="toggle"]')
  }

  // # Connect

  it('starts collapsed', () => {
    expect(element.classList.contains('is-collapsed')).toBe(true)
  })

  it('sets toggle text to "show more" when collapsed', () => {
    expect(toggleBtn().textContent).toBe('show more')
  })

  // # Expand

  it('removes collapsed class on expand', () => {
    ctrl().expand()
    expect(element.classList.contains('is-collapsed')).toBe(false)
  })

  it('sets toggle text to "show less" on expand', () => {
    ctrl().expand()
    expect(toggleBtn().textContent).toBe('show less')
  })

  // # Collapse

  it('adds collapsed class on collapse', () => {
    ctrl().expand()
    ctrl().collapse()
    expect(element.classList.contains('is-collapsed')).toBe(true)
  })

  it('sets toggle text to "show more" on collapse', () => {
    ctrl().expand()
    ctrl().collapse()
    expect(toggleBtn().textContent).toBe('show more')
  })

  // # Toggle

  it('toggle expands when currently collapsed', () => {
    ctrl().toggle()
    expect(element.classList.contains('is-collapsed')).toBe(false)
  })

  it('toggle collapses when currently expanded', () => {
    ctrl().expand()
    ctrl().toggle()
    expect(element.classList.contains('is-collapsed')).toBe(true)
  })
})
