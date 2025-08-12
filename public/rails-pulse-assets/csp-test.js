// CSP Test JavaScript
// This file tests that external JS files load correctly under strict CSP

(function() {
  'use strict';
  
  function updateStatus(elementId, status, success) {
    const element = document.getElementById(elementId);
    if (element) {
      element.textContent = status;
      element.className = success ? 'badge badge--success' : 'badge badge--error';
    }
  }
  
  function checkAssetLoading() {
    // Check CSS loading
    const cssLoaded = document.querySelector('link[href*="rails-pulse.css"]');
    updateStatus('css-status', cssLoaded ? 'Loaded' : 'Failed', !!cssLoaded);
    
    // Check if main JS bundle exists (has Stimulus controllers)
    const hasStimulus = window.Stimulus !== undefined;
    updateStatus('js-status', hasStimulus ? 'Loaded' : 'Failed', hasStimulus);
    
    // Check icons bundle (should have icon definitions)
    const hasIcons = document.querySelector('script[src*="rails-pulse-icons.js"]');
    updateStatus('icons-status', hasIcons ? 'Loaded' : 'Failed', !!hasIcons);
    
    // Check Stimulus controllers are registered
    const stimulusControllers = hasStimulus && window.Stimulus.router.modulesByIdentifier.size > 0;
    updateStatus('stimulus-status', stimulusControllers ? 'Active' : 'Failed', stimulusControllers);
  }
  
  function setupAjaxTest() {
    const button = document.getElementById('ajax-test-btn');
    const result = document.getElementById('ajax-result');
    
    if (button && result) {
      button.addEventListener('click', async () => {
        try {
          button.disabled = true;
          button.textContent = 'Loading...';
          
          // Test a simple fetch request
          const response = await fetch('/rails_pulse/csp_test', {
            headers: { 'Accept': 'application/json' }
          });
          
          const data = await response.json();
          
          result.innerHTML = `
            <div class="text-success">✓ AJAX request completed successfully</div>
            <div class="text-subtle mt-1">Status: ${response.status} ${response.statusText}</div>
            <div class="text-subtle mt-1">Response: ${data.message}</div>
          `;
        } catch (error) {
          result.innerHTML = `
            <div class="text-error">✗ AJAX request failed</div>
            <div class="text-subtle mt-1">Error: ${error.message}</div>
          `;
        } finally {
          button.disabled = false;
          button.textContent = 'Test AJAX Loading';
        }
      });
    }
  }
  
  function trackCSPViolations() {
    let violationCount = 0;
    const countElement = document.getElementById('violation-count');
    
    // Listen for CSP violations
    document.addEventListener('securitypolicyviolation', (event) => {
      violationCount++;
      if (countElement) {
        countElement.textContent = violationCount;
        countElement.className = violationCount > 0 ? 'badge badge--error' : 'badge badge--success';
      }
      console.warn('CSP Violation:', event.violatedDirective, event.blockedURI);
    });
    
    // Initialize count display
    if (countElement) {
      countElement.textContent = '0';
      countElement.className = 'badge badge--success';
    }
  }
  
  function initializeTests() {
    checkAssetLoading();
    setupAjaxTest();
    trackCSPViolations();
  }
  
  // Run tests when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeTests);
  } else {
    initializeTests();
  }
  
  console.log('CSP Test JS loaded successfully - monitoring for violations');
  
  // Add a visible indicator for system tests
  const indicator = document.createElement('div');
  indicator.id = 'js-loaded-indicator';
  indicator.textContent = 'CSP Test JS loaded successfully';
  indicator.style.display = 'none'; // Hidden but accessible to tests
  document.body.appendChild(indicator);
})();