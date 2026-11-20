import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import TableSortController from '../../../app/javascript/rails_pulse/controllers/table_sort_controller'
import { mountController, controllableFetch, nextTick } from '../setup'

const HTML = `
  <div data-controller="table-sort">
    <div id="index_table" data-table-sort-target="tableFrame">
      <a id="by-path" href="/routes?q[s]=path" data-action="click->table-sort#updateUrl">Path</a>
      <a id="by-method" href="/routes?q[s]=method" data-action="click->table-sort#updateUrl">Method</a>
      <a data-action="click->table-sort#updateUrl">No href</a>
      <p>Old rows</p>
    </div>
  </div>
`

function tableHtml(label) {
  return `<div id="index_table"><p>${label} rows</p></div>`
}

describe('TableSortController', () => {
  let app, element, teardown, pending

  beforeEach(async () => {
    vi.spyOn(window.history, 'replaceState').mockImplementation(() => {})
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const fetchControl = controllableFetch()
    pending = fetchControl.pending
    vi.stubGlobal('fetch', fetchControl.fetchMock)
    ;({ app, element, teardown } = await mountController('table-sort', TableSortController, HTML))
  })

  afterEach(() => {
    teardown()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'table-sort')
  }

  function click(selector) {
    ctrl().updateUrl({ preventDefault: vi.fn(), currentTarget: element.querySelector(selector) })
  }

  function table() {
    return element.querySelector('#index_table')
  }

  // # updateUrl

  it('updates the browser URL via history.replaceState', () => {
    click('#by-path')
    expect(window.history.replaceState).toHaveBeenCalledWith({}, '', '/routes?q[s]=path')
  })

  it('fetches the sorted table and replaces the frame', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond(tableHtml('Path'))
    await nextTick()
    expect(table().textContent).toBe('Path rows')
    expect(table().hasAttribute('aria-busy')).toBe(false)
  })

  it('marks the table busy while the fetch is in flight', () => {
    click('#by-path')
    expect(table().getAttribute('aria-busy')).toBe('true')
  })

  it('shows a spinner on the clicked header until the response arrives', () => {
    click('#by-path')
    expect(element.querySelector('#by-path').hasAttribute('data-sort-loading')).toBe(true)

    click('#by-method')
    expect(element.querySelector('#by-path').hasAttribute('data-sort-loading')).toBe(false)
    expect(element.querySelector('#by-method').hasAttribute('data-sort-loading')).toBe(true)
  })

  it('does nothing when the link has no href', () => {
    click('a:not([href])')
    expect(window.history.replaceState).not.toHaveBeenCalled()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('prevents default on the event', () => {
    const preventDefault = vi.fn()
    ctrl().updateUrl({ preventDefault, currentTarget: element.querySelector('#by-path') })
    expect(preventDefault).toHaveBeenCalledOnce()
  })

  // # Edge Cases

  it('keeps the newest sort when an older response arrives last', async () => {
    click('#by-path')
    click('#by-method')

    pending['/routes?q[s]=method'].respond(tableHtml('Method'))
    await nextTick()
    pending['/routes?q[s]=path'].respond(tableHtml('Path'))
    await nextTick()

    expect(table().textContent).toBe('Method rows')
    expect(console.error).not.toHaveBeenCalled()
  })

  it('replaces the old rows with an error notice when the fetch fails', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('Server error', 500)
    await nextTick()

    const notice = table().querySelector('[role="alert"]')
    expect(notice).not.toBeNull()
    expect(notice.textContent).toContain('Could not load the table.')
    expect(table().textContent).not.toContain('Old rows')
    expect(table().hasAttribute('aria-busy')).toBe(false)
  })

  it('retries the failed fetch from the error notice', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('Server error', 500)
    await nextTick()

    table().querySelector('[role="alert"] button').click()
    pending['/routes?q[s]=path'].respond(tableHtml('Path'))
    await nextTick()

    expect(fetch).toHaveBeenCalledTimes(2)
    expect(table().textContent).toBe('Path rows')
  })

  it('sends one request when the same sort is clicked again while loading', async () => {
    click('#by-path')
    click('#by-path')
    pending['/routes?q[s]=path'].respond(tableHtml('Path'))
    await nextTick()

    expect(fetch).toHaveBeenCalledOnce()
    expect(table().textContent).toBe('Path rows')
  })

  it('explains a server error in the notice', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('Server error', 503)
    await nextTick()

    expect(table().querySelector('.fetch-error__title').textContent).toBe('Could not load the table.')
    expect(table().querySelector('.fetch-error__detail').textContent).toContain('HTTP 503')
  })

  it('explains a network failure in the notice', async () => {
    fetch.mockImplementationOnce(() => Promise.reject(new TypeError('Failed to fetch')))
    click('#by-path')
    await nextTick()

    expect(table().querySelector('.fetch-error__detail').textContent).toContain('Check your connection')
  })

  it('shows an error notice when the response lacks the table, as a sign-in redirect would', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('<html><body><h1>Sign in</h1></body></html>')
    await nextTick()

    const notice = table().querySelector('[role="alert"]')
    expect(notice).not.toBeNull()
    expect(notice.textContent).toContain('The server returned an unexpected page.')
    expect(notice.querySelector('button').textContent).toBe('Retry')
    expect(console.error).not.toHaveBeenCalled()
  })

  it('moves focus to the table after a successful retry', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('Server error', 500)
    await nextTick()

    const button = table().querySelector('.fetch-error button')
    button.focus()
    button.click()
    expect(button.getAttribute('aria-disabled')).toBe('true')
    expect(button.textContent).toBe('Retrying…')

    pending['/routes?q[s]=path'].respond(tableHtml('Path'))
    await nextTick()

    expect(document.activeElement).toBe(table())
  })

  it('moves focus to the new Retry button when the retry fails again', async () => {
    click('#by-path')
    pending['/routes?q[s]=path'].respond('Server error', 500)
    await nextTick()

    table().querySelector('.fetch-error button').click()
    pending['/routes?q[s]=path'].respond('Server error', 500)
    await nextTick()

    const button = table().querySelector('.fetch-error button')
    expect(document.activeElement).toBe(button)
    expect(button.hasAttribute('aria-disabled')).toBe(false)
  })
})
