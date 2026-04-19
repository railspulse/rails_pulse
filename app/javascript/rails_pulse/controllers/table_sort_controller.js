import { Controller } from "@hotwired/stimulus"
import { fetchAndReplace } from "../utils/fetch_helpers"

export default class extends Controller {
  static targets = ["tableFrame"]

  updateUrl(event) {
    event.preventDefault()
    const link = event.currentTarget
    const href = link.getAttribute('href')

    if (href) {
      window.history.replaceState({}, '', href)
      this.fetchAndUpdateTable(href)
    }
  }

  async fetchAndUpdateTable(url) {
    try {
      await fetchAndReplace(url, this.tableFrameTarget)
    } catch (error) {
      console.error('Table sort error:', error)
    }
  }
}
