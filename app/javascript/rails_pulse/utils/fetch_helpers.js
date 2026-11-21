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
  const { headers, ...fetchOptions } = options
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
    ...fetchOptions,
    method: method,
    headers: { ...defaultHeaders, ...headers }
  })

  if (!response.ok) {
    const error = new Error(`HTTP error! status: ${response.status}`)
    error.status = response.status
    throw error
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
  // The parsed response is discarded afterwards, so its nodes are moved, not cloned
  targetElement.replaceChildren(...sourceElement.childNodes)
}

// In-flight request per target element: { url, controller, promise }
const inFlight = new WeakMap()

/**
 * Fetch HTML and replace a target element's content in one operation.
 * Asking again for the URL already loading into the element returns that request;
 * a different URL aborts it (rejecting with an AbortError), so a slow response can
 * never overwrite a newer one. While loading, the element carries aria-busy="true".
 * @param {string} url - The URL to fetch
 * @param {HTMLElement} targetElement - Element to update
 * @param {Object} options - Additional fetch options
 * @param {string} options.selector - CSS selector to find content in response (defaults to targetElement.id)
 * @returns {Promise<boolean>} - True if content was replaced, false if selector not found in response
 */
export function fetchAndReplace(url, targetElement, options = {}) {
  const current = inFlight.get(targetElement)
  if (current?.url === url) return current.promise

  current?.controller.abort()
  const controller = new AbortController()
  const promise = replaceFrom(url, targetElement, options, controller)
  inFlight.set(targetElement, { url, controller, promise })
  return promise
}

async function replaceFrom(url, targetElement, options, controller) {
  targetElement.setAttribute('aria-busy', 'true')

  try {
    const doc = await fetchPartial(url, { ...options, signal: controller.signal })
    // A response can still settle after abort() if the body was already read
    controller.signal.throwIfAborted()

    // Use provided selector or default to target element's ID
    const selector = options.selector || `#${targetElement.id}`
    const sourceElement = doc.querySelector(selector)

    if (sourceElement) {
      replaceElement(targetElement, sourceElement)
      return true
    }

    // No matching content in response - clear the target
    targetElement.replaceChildren()
    return false
  } finally {
    if (inFlight.get(targetElement)?.controller === controller) {
      inFlight.delete(targetElement)
      targetElement.removeAttribute('aria-busy')
    }
  }
}

/**
 * Fetch and replace, showing an error notice with a Retry button in the target
 * when the fetch fails or the response lacks the expected content. A fetch
 * superseded by a newer one is ignored silently.
 * @param {string} url - The URL to fetch
 * @param {HTMLElement} targetElement - Element to update
 * @param {Object} options - Options for fetchAndReplace, plus:
 * @param {string} options.errorMessage - Headline for the error notice
 * @returns {Promise<boolean>} - True if content was replaced; false on failure or abort
 */
export async function loadInto(url, targetElement, options = {}) {
  const { errorMessage = 'Could not load this content.', ...fetchOptions } = options
  const retry = () => retryInto(url, targetElement, options)

  try {
    if (await fetchAndReplace(url, targetElement, fetchOptions)) return true
    // Every page renders the target, empty state included, so a 200 without it is
    // a page the dashboard did not render: a host sign-in redirect or a proxy page.
    showFetchError(targetElement, errorMessage, MISSING_CONTENT_DETAIL, retry)
    return false
  } catch (error) {
    if (error?.name === 'AbortError') return false
    console.error('[RailsPulse] Fetch error:', error)
    showFetchError(targetElement, errorMessage, errorDetail(error), retry)
    return false
  }
}

const MISSING_CONTENT_DETAIL = 'The server returned an unexpected page. Reloading the page usually fixes this.'

function errorDetail(error) {
  if (error?.status >= 500) return `The server ran into a problem (HTTP ${error.status}). Try again in a moment.`
  if (error?.status) return `The server refused the request (HTTP ${error.status}). Reload the page and try again.`
  return 'Could not reach the server. Check your connection and try again.'
}

// Keyboard focus sits on the Retry button, which the response replaces: move it
// to the new content, or to the next notice's button if the retry fails too.
async function retryInto(url, targetElement, options) {
  const button = targetElement.querySelector('.fetch-error button')
  if (button?.getAttribute('aria-disabled') === 'true') return
  if (button) {
    button.setAttribute('aria-disabled', 'true')
    button.lastChild.textContent = 'Retrying…'
  }

  const loaded = await loadInto(url, targetElement, options)
  if (loaded) {
    targetElement.setAttribute('tabindex', '-1')
    targetElement.focus({ preventScroll: true })
  } else {
    targetElement.querySelector('.fetch-error button')?.focus()
  }
}

function showFetchError(targetElement, message, detail, retry) {
  const notice = document.createElement('div')
  notice.className = 'alert alert--negative fetch-error'
  notice.setAttribute('role', 'alert')

  const icon = document.createElement('span')
  icon.className = 'fetch-error__icon'
  icon.setAttribute('aria-hidden', 'true')
  window.RailsPulseIcons?.render('alert-circle', icon, { width: '20', height: '20' })

  const body = document.createElement('div')
  body.className = 'fetch-error__body'
  const title = document.createElement('p')
  title.className = 'fetch-error__title'
  title.textContent = message
  const text = document.createElement('p')
  text.className = 'fetch-error__detail'
  text.textContent = detail
  body.append(title, text)

  const button = document.createElement('button')
  button.type = 'button'
  button.className = 'btn'
  const buttonIcon = document.createElement('span')
  buttonIcon.setAttribute('aria-hidden', 'true')
  window.RailsPulseIcons?.render('refresh-cw', buttonIcon, { width: '16', height: '16' })
  button.append(buttonIcon, document.createTextNode('Retry'))
  button.addEventListener('click', retry)

  notice.append(icon, body, button)
  targetElement.replaceChildren(notice)
}
