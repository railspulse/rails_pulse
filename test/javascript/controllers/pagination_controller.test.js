import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import PaginationController from '../../../app/javascript/rails_pulse/controllers/pagination_controller'
import { mountController } from '../setup'

function buildHTML(selectValue = '25') {
  return `
    <div data-controller="pagination">
      <select data-pagination-target="limit">
        <option value="25" ${selectValue === '25' ? 'selected' : ''}>25</option>
        <option value="50" ${selectValue === '50' ? 'selected' : ''}>50</option>
        <option value="100" ${selectValue === '100' ? 'selected' : ''}>100</option>
      </select>
    </div>
  `
}

describe('PaginationController', () => {
  let app, element, teardown

  beforeEach(() => {
    sessionStorage.clear()
  })

  afterEach(() => teardown?.())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'pagination')
  }

  function limitSelect() {
    return element.querySelector('select')
  }

  // # restorePaginationLimit on connect

  it('syncs select value from URL param on connect', async () => {
    vi.stubGlobal('location', { href: 'http://localhost/?limit=50', search: '?limit=50' })
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML()))
    expect(limitSelect().value).toBe('50')
    vi.unstubAllGlobals()
  })

  it('syncs sessionStorage when URL param is present', async () => {
    vi.stubGlobal('location', { href: 'http://localhost/?limit=100', search: '?limit=100' })
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML()))
    expect(sessionStorage.getItem('rails_pulse_pagination_limit')).toBe('100')
    vi.unstubAllGlobals()
  })

  it('falls back to sessionStorage when no URL param', async () => {
    sessionStorage.setItem('rails_pulse_pagination_limit', '50')
    vi.stubGlobal('location', { href: 'http://localhost/', search: '' })
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML()))
    expect(limitSelect().value).toBe('50')
    vi.unstubAllGlobals()
  })

  it('leaves select unchanged when no URL param and no sessionStorage', async () => {
    vi.stubGlobal('location', { href: 'http://localhost/', search: '' })
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML('25')))
    expect(limitSelect().value).toBe('25')
    vi.unstubAllGlobals()
  })

  // # updateLimit

  it('saves selected limit to sessionStorage', async () => {
    const locationMock = { href: 'http://localhost/', search: '', toString() { return this.href } }
    vi.stubGlobal('location', locationMock)
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML()))
    limitSelect().value = '100'
    ctrl().updateLimit()
    expect(sessionStorage.getItem('rails_pulse_pagination_limit')).toBe('100')
    vi.unstubAllGlobals()
  })

  it('navigates to the URL with the new limit and no page param', async () => {
    const locationMock = { href: 'http://localhost/?page=3', search: '?page=3', toString() { return this.href } }
    vi.stubGlobal('location', locationMock)
    ;({ app, element, teardown } = await mountController('pagination', PaginationController, buildHTML()))
    limitSelect().value = '50'
    ctrl().updateLimit()
    expect(locationMock.href).toMatch(/limit=50/)
    expect(locationMock.href).not.toMatch(/page=/)
    vi.unstubAllGlobals()
  })

  // # missing limit target

  it('connects without a limit target instead of throwing', async () => {
    // Accessing a missing Stimulus target throws, so guarding on truthiness
    // rather than hasLimitTarget used to break connect() outright.
    vi.stubGlobal('location', { href: 'http://localhost/?limit=50', search: '?limit=50' })
    ;({ app, element, teardown } = await mountController(
      'pagination',
      PaginationController,
      '<div data-controller="pagination"></div>'
    ))
    // Stimulus swallows errors thrown in connect(), so call the method directly.
    expect(() => ctrl().restorePaginationLimit()).not.toThrow()
    vi.unstubAllGlobals()
  })
})
