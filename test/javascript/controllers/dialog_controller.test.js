import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import DialogController from '../../../app/javascript/rails_pulse/controllers/dialog_controller'
import { mountController } from '../setup'

// JSDOM has partial <dialog> support — spy on the methods directly.
const HTML = `
  <div data-controller="dialog">
    <dialog data-dialog-target="menu"></dialog>
  </div>
`

describe('DialogController', () => {
  let app, element, teardown, dialogEl

  beforeEach(async () => {
    ;({ app, element, teardown } = await mountController('dialog', DialogController, HTML))
    dialogEl = element.querySelector('dialog')
    // JSDOM may not implement these; ensure they exist as spies
    dialogEl.show = vi.fn()
    dialogEl.showModal = vi.fn()
    dialogEl.close = vi.fn()
  })

  afterEach(() => teardown())

  function ctrl() {
    return app.getControllerForElementAndIdentifier(element, 'dialog')
  }

  it('show() calls show() on the dialog', () => {
    ctrl().show()
    expect(dialogEl.show).toHaveBeenCalledOnce()
  })

  it('showModal() calls showModal() on the dialog', () => {
    ctrl().showModal()
    expect(dialogEl.showModal).toHaveBeenCalledOnce()
  })

  it('close() calls close() on the dialog', () => {
    ctrl().close()
    expect(dialogEl.close).toHaveBeenCalledOnce()
  })

  it('closeOnClickOutside closes when the target is the DIALOG element', () => {
    ctrl().closeOnClickOutside({ target: dialogEl })
    expect(dialogEl.close).toHaveBeenCalledOnce()
  })

  it('closeOnClickOutside does not close when target is not the dialog', () => {
    const btn = document.createElement('button')
    ctrl().closeOnClickOutside({ target: btn })
    expect(dialogEl.close).not.toHaveBeenCalled()
  })
})
