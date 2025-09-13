import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  updateUrl(event) {
    // Get the href from the clicked link
    const link = event.currentTarget;
    const href = link.getAttribute('href');
    
    if (href) {
      // Update the browser URL to match the sort link
      window.history.replaceState({}, '', href);
    }
  }
}