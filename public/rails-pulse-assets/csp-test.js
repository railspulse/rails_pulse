// CSP Test functionality
// Tests asset loading and AJAX requests under strict Content Security Policy

document.addEventListener('DOMContentLoaded', function() {
  // Check asset loading status
  checkAssetLoadingStatus();

  // Setup AJAX button
  setupAjaxButton();

  // Check for CSP violations
  checkCspViolations();
});

function checkAssetLoadingStatus() {
  const cssStatus = document.getElementById('css-status');
  const jsStatus = document.getElementById('js-status');
  const iconsStatus = document.getElementById('icons-status');
  const stimulusStatus = document.getElementById('stimulus-status');

  // Check if CSS is loaded by testing if styles are applied
  if (cssStatus) {
    const testElement = document.querySelector('.card');
    if (testElement && getComputedStyle(testElement).backgroundColor !== 'rgba(0, 0, 0, 0)') {
      cssStatus.textContent = 'Loaded';
      cssStatus.className = 'badge badge--success';
    } else {
      cssStatus.textContent = 'Failed';
      cssStatus.className = 'badge badge--error';
    }
  }

  // Check if JS is loaded (this script proves it)
  if (jsStatus) {
    jsStatus.textContent = 'Loaded';
    jsStatus.className = 'badge badge--success';
  }

  // Check if icons script is loaded
  if (iconsStatus) {
    if (typeof window.RailsPulseIcons !== 'undefined') {
      iconsStatus.textContent = 'Loaded';
      iconsStatus.className = 'badge badge--success';
    } else {
      iconsStatus.textContent = 'Failed';
      iconsStatus.className = 'badge badge--error';
    }
  }

  // Check if Stimulus is active
  if (stimulusStatus) {
    if (window.Stimulus && typeof window.Stimulus.getControllerForElementAndIdentifier === 'function') {
      stimulusStatus.textContent = 'Active';
      stimulusStatus.className = 'badge badge--success';
    } else {
      stimulusStatus.textContent = 'Inactive';
      stimulusStatus.className = 'badge badge--error';
    }
  }
}

function setupAjaxButton() {
  const ajaxButton = document.getElementById('ajax-test-btn');
  const ajaxResult = document.getElementById('ajax-result');

  if (ajaxButton && ajaxResult) {
    ajaxButton.addEventListener('click', function() {
      // Update UI to show loading state
      ajaxButton.disabled = true;
      ajaxButton.textContent = 'Loading...';
      ajaxResult.innerHTML = '<span class="text-subtle">Making AJAX request...</span>';

      // Make AJAX request to the JSON endpoint
      fetch('/rails_pulse/csp_test.json', {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        credentials: 'same-origin'
      })
      .then(response => {
        if (!response.ok) {
          throw new Error('Network response was not ok');
        }
        return response.json();
      })
      .then(data => {
        // Success - display the success message
        ajaxResult.innerHTML = '<span class="text-success">AJAX request completed successfully</span>';
        ajaxButton.textContent = 'Test AJAX Loading';
        ajaxButton.disabled = false;
      })
      .catch(error => {
        // Error handling
        console.error('AJAX request failed:', error);
        ajaxResult.innerHTML = '<span class="text-error">AJAX request failed: ' + error.message + '</span>';
        ajaxButton.textContent = 'Test AJAX Loading';
        ajaxButton.disabled = false;
      });
    });
  }
}

function checkCspViolations() {
  const violationCount = document.getElementById('violation-count');

  if (violationCount) {
    // Start with 0 violations and mark as success immediately
    let violations = 0;
    violationCount.className = 'badge badge--success';

    // Listen for CSP violations
    document.addEventListener('securitypolicyviolation', function() {
      violations++;
      violationCount.textContent = violations.toString();
      violationCount.className = 'badge badge--error';
    });
  }
}
