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
  
  // Run checks when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', checkAssetLoading);
  } else {
    checkAssetLoading();
  }
  
  console.log('CSP Test JS loaded successfully - no CSP violations');
})();