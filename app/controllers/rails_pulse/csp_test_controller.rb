# CSP Test Controller for Rails Pulse
# Tests Content Security Policy compliance with strict policies

class RailsPulse::CspTestController < RailsPulse::ApplicationController
  # Strict CSP configuration for testing
  before_action :set_strict_csp

  def show
    # Test page that validates CSP compliance
    render :show
  end

  private

  def set_strict_csp
    # Strict Content Security Policy for testing CSP compliance
    # Note: Currently allows some unsafe practices due to third-party dependencies
    # TODO: Full CSP compliance requires addressing rails_charts gem inline scripts
    response.headers["Content-Security-Policy"] = [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{request_nonce}' 'unsafe-inline'",  # rails_charts generates inline scripts
      "style-src 'self' 'nonce-#{request_nonce}'",
      "style-src-attr 'unsafe-inline'",  # TODO: Remove this and fix inline styles
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self'",
      "frame-src 'none'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join("; ")
  end

  def request_nonce
    @request_nonce ||= SecureRandom.base64(32)
  end

  helper_method :request_nonce
end
