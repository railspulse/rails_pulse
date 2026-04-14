import { Controller } from "@hotwired/stimulus"
import { fetchPartial, replaceElement } from "../utils/fetch_helpers"

export default class extends Controller {
  static targets = ["analysisSection"]

  async analyze(event) {
    event.preventDefault()

    const link = event.currentTarget
    const url = link.dataset.analyzeUrl

    if (!url) {
      console.error('No analyze URL provided')
      return
    }

    try {
      // Add loading class to link
      link.classList.add('opacity-50', 'pointer-events-none')

      // Fetch the analysis with POST
      const doc = await fetchPartial(url, { method: 'POST' })

      // Find the updated analysis section in the response
      const newAnalysis = doc.querySelector('#query_analysis')

      if (newAnalysis && this.hasAnalysisSectionTarget) {
        replaceElement(this.analysisSectionTarget, newAnalysis)
      }
    } catch (error) {
      console.error('Query analysis error:', error)
    } finally {
      // Remove loading class (if link still exists after replacement)
      if (link && link.parentElement) {
        link.classList.remove('opacity-50', 'pointer-events-none')
      }
    }
  }
}
