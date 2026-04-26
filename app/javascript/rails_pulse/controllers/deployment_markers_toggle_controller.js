import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    const isActive = this.element.dataset.active !== 'false'
    this.element.dataset.active = isActive ? 'false' : 'true'

    document.dispatchEvent(new CustomEvent('rails-pulse:toggle-deployment-markers', {
      detail: { visible: !isActive }
    }))
  }
}
