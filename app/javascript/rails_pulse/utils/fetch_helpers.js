/**
 * Shared utilities for fetching partial HTML and replacing DOM content
 * Used across Rails Pulse controllers for in-place updates without full page reloads
 */

/**
 * Get CSRF token from meta tag
 * @returns {string|null} - CSRF token or null
 */
function getCsrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.content : null
}

/**
 * Fetch HTML from a URL with partial request headers
 * @param {string} url - The URL to fetch
 * @param {Object} options - Additional fetch options (merged with defaults)
 * @returns {Promise<Document>} - Parsed HTML document
 */
export async function fetchPartial(url, options = {}) {
  const defaultHeaders = {
    'Accept': 'text/html',
    'X-Partial-Request': 'true',
    'X-Requested-With': 'XMLHttpRequest'
  }

  // Add CSRF token for non-GET requests
  const method = options.method || 'GET'
  if (method !== 'GET') {
    const csrfToken = getCsrfToken()
    if (csrfToken) {
      defaultHeaders['X-CSRF-Token'] = csrfToken
    }
  }

  const response = await fetch(url, {
    method: method,
    headers: { ...defaultHeaders, ...options.headers },
    ...options
  })

  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`)
  }

  const html = await response.text()
  const parser = new DOMParser()
  return parser.parseFromString(html, 'text/html')
}

/**
 * Replace the content of a target element with content from a source element
 * Uses safe DOM methods (no innerHTML) for CSP compliance
 * @param {HTMLElement} targetElement - Element to update
 * @param {HTMLElement} sourceElement - Element containing new content
 */
export function replaceElement(targetElement, sourceElement) {
  // Clear existing content
  while (targetElement.firstChild) {
    targetElement.removeChild(targetElement.firstChild)
  }

  // Clone and append new content
  Array.from(sourceElement.childNodes).forEach(child => {
    targetElement.appendChild(child.cloneNode(true))
  })
}

/**
 * Fetch HTML and replace a target element's content in one operation
 * @param {string} url - The URL to fetch
 * @param {HTMLElement} targetElement - Element to update
 * @param {Object} options - Additional fetch options
 * @param {string} options.selector - CSS selector to find content in response (defaults to targetElement.id)
 * @returns {Promise<boolean>} - True if content was replaced, false if selector not found in response
 */
export async function fetchAndReplace(url, targetElement, options = {}) {
  const doc = await fetchPartial(url, options)

  // Use provided selector or default to target element's ID
  const selector = options.selector || `#${targetElement.id}`
  const sourceElement = doc.querySelector(selector)

  if (sourceElement) {
    replaceElement(targetElement, sourceElement)
    return true
  }

  // No matching content in response - clear the target
  while (targetElement.firstChild) {
    targetElement.removeChild(targetElement.firstChild)
  }
  return false
}
