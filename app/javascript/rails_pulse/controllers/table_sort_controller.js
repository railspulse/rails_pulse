import { Controller } from "@hotwired/stimulus"
import { loadInto } from "../utils/fetch_helpers"

export default class extends Controller {
  static targets = ["tableFrame"]

  updateUrl(event) {
    event.preventDefault()
    const link = event.currentTarget
    const href = link.getAttribute('href')

    if (href) {
      window.history.replaceState({}, '', href)
      this.markLoading(link)
      this.fetchAndUpdateTable(href)
    }
  }

  // The sort arrows come from the server, so until the response replaces the
  // header the clicked column shows a spinner instead.
  markLoading(link) {
    this.tableFrameTarget.querySelectorAll('[data-sort-loading]').forEach(el => el.removeAttribute('data-sort-loading'))
    if (this.tableFrameTarget.contains(link)) link.setAttribute('data-sort-loading', '')
  }

  fetchAndUpdateTable(url) {
    return loadInto(url, this.tableFrameTarget, { errorMessage: 'Could not load the table.' })
  }
}
