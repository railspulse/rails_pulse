import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import FormController from '../../../app/javascript/rails_pulse/controllers/form_controller'
import { mountController } from '../setup'

const HTML = `
  <form data-controller="form">
    <input type="text" />
    <a href="#" data-form-target="cancel">Cancel</a>
  </form>
`

describe('FormController', () => {
  let app, element, teardown

  beforeEach(async () => {
    ;({ app, element, teardown } = await mountController('form', FormController, HTML))
    element.requestSubmit = vi.fn()
  })

  afterEach(() => teardown())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'form')
  }

  // # Submit

  it('submit() calls requestSubmit() on the form', () => {
    ctrl().submit()
    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  // # Cancel

  it('cancel() clicks the cancel target', () => {
    const cancelLink = element.querySelector('[data-form-target="cancel"]')
    const clickSpy = vi.spyOn(cancelLink, 'click')
    ctrl().cancel()
    expect(clickSpy).toHaveBeenCalledOnce()
  })

  // # preventAttachment

  it('preventAttachment() calls event.preventDefault()', () => {
    const event = { preventDefault: vi.fn() }
    ctrl().preventAttachment(event)
    expect(event.preventDefault).toHaveBeenCalledOnce()
  })

  // # Debounce (search)

  it('search is debounced — only submits once after the delay', async () => {
    vi.useFakeTimers()
    const c = ctrl()
    c.search()
    c.search()
    c.search()
    expect(element.requestSubmit).not.toHaveBeenCalled()
    vi.advanceTimersByTime(500)
    expect(element.requestSubmit).toHaveBeenCalledOnce()
    vi.useRealTimers()
  })
})
