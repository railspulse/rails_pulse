import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import TableSortController from '../../../app/javascript/rails_pulse/controllers/table_sort_controller'
import { mountController } from '../setup'

vi.mock('../../../app/javascript/rails_pulse/utils/fetch_helpers', () => ({
  fetchAndReplace: vi.fn().mockResolvedValue(true),
}))

import { fetchAndReplace } from '../../../app/javascript/rails_pulse/utils/fetch_helpers'

const HTML = `
  <div data-controller="table-sort">
    <div id="sort-table" data-table-sort-target="tableFrame">Table content</div>
    <a href="/requests?sort=name&direction=asc" data-action="click->table-sort#updateUrl">Name</a>
    <a data-action="click->table-sort#updateUrl">No href</a>
  </div>
`

describe('TableSortController', () => {
  let app, element, teardown

  beforeEach(async () => {
    vi.spyOn(window.history, 'replaceState').mockImplementation(() => {})
    ;({ app, element, teardown } = await mountController('table-sort', TableSortController, HTML))
  })

  afterEach(() => {
    teardown()
    vi.clearAllMocks()
  })

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'table-sort')
  }

  function linkWithHref() {
    return element.querySelector('a[href]')
  }

  function linkWithoutHref() {
    return element.querySelector('a:not([href])')
  }

  // # updateUrl

  it('updates the browser URL via history.replaceState', () => {
    ctrl().updateUrl({ preventDefault: vi.fn(), currentTarget: linkWithHref() })
    expect(window.history.replaceState).toHaveBeenCalledWith(
      {},
      '',
      '/requests?sort=name&direction=asc'
    )
  })

  it('fetches and replaces the table frame', () => {
    const tableFrame = element.querySelector('#sort-table')
    ctrl().updateUrl({ preventDefault: vi.fn(), currentTarget: linkWithHref() })
    expect(fetchAndReplace).toHaveBeenCalledWith(
      '/requests?sort=name&direction=asc',
      tableFrame
    )
  })

  it('does nothing when the link has no href', () => {
    ctrl().updateUrl({ preventDefault: vi.fn(), currentTarget: linkWithoutHref() })
    expect(window.history.replaceState).not.toHaveBeenCalled()
    expect(fetchAndReplace).not.toHaveBeenCalled()
  })

  it('prevents default on the event', () => {
    const preventDefault = vi.fn()
    ctrl().updateUrl({ preventDefault, currentTarget: linkWithHref() })
    expect(preventDefault).toHaveBeenCalledOnce()
  })
})
