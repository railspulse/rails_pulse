import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "message"]

  connect() {
    this.syncUi()
  }

  toggle() {
    const isActive = this.element.dataset.active !== 'false'
    this.element.dataset.active = isActive ? 'false' : 'true'
    this.syncUi()

    document.dispatchEvent(new CustomEvent('rails-pulse:toggle-deployment-markers', {
      detail: { visible: !isActive }
    }))
  }

  syncUi() {
    const isActive = this.element.dataset.active !== 'false'

    if (this.hasButtonTarget) {
      this.buttonTarget.dataset.active = isActive ? 'true' : 'false'
    }

    if (this.hasMessageTarget) {
      this.messageTarget.style.display = isActive ? 'inline' : 'none'
    }
  }
}
