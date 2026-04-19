module RailsPulse
  module CspHelper
    # CSP nonce helper for Rails Pulse
    # Detects Content Security Policy nonces from various common patterns in Rails apps
    def rails_pulse_csp_nonce
      # Try various methods to get the CSP nonce from the host application
      nonce = nil

      # Method 1: Check for Rails 6+ CSP nonce helper
      if respond_to?(:content_security_policy_nonce)
        nonce = content_security_policy_nonce
      end

      # Method 2: Check for custom csp_nonce helper (common in many apps)
      if nonce.blank? && respond_to?(:csp_nonce)
        nonce = csp_nonce
      end

      # Method 3: Try to extract from request environment (where CSP gems often store it)
      if nonce.blank? && defined?(request) && request
        nonce = request.env["action_dispatch.content_security_policy_nonce"] ||
                request.env["secure_headers.content_security_policy_nonce"] ||
                request.env["csp_nonce"]
      end

      # Method 4: Check content_for CSP nonce (some apps set it this way)
      if nonce.blank? && respond_to?(:content_for) && content_for?(:csp_nonce)
        nonce = content_for(:csp_nonce)
      end

      # Method 5: Extract from meta tag if present (less efficient but works)
      if nonce.blank? && defined?(content_security_policy_nonce_tag)
        begin
          tag_content = content_security_policy_nonce_tag
          if tag_content && tag_content.include?("nonce-")
            nonce = tag_content.match(/nonce-([^"']+)/)[1] if tag_content.match(/nonce-([^"']+)/)
          end
        rescue
          # Ignore parsing errors
        end
      end

      # Return the nonce or nil (Rails will handle CSP properly with nil)
      nonce.presence
    end
  end
end
