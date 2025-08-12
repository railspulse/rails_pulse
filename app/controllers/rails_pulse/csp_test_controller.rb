# CSP Test Controller for Rails Pulse
# Tests Content Security Policy compliance with strict policies

class RailsPulse::CspTestController < RailsPulse::ApplicationController
  # Strict CSP configuration for testing
  before_action :set_strict_csp

  def show
    respond_to do |format|
      format.html { render :show }
      format.json { render json: { status: "ok", message: "CSP test endpoint working" } }
    end
  end

  private

  def set_strict_csp
    # Strict Content Security Policy for testing Rails Pulse CSP compliance
    csp_directives = {
      "default-src" => "'self'",
      "script-src" => build_script_src,
      "style-src" => build_style_src,
      "style-src-attr" => "'unsafe-hashes' 'unsafe-inline'",  # CSS custom properties
      "img-src" => "'self' data:",
      "font-src" => "'self'",
      "connect-src" => "'self'",
      "frame-src" => "'none'",
      "object-src" => "'none'",
      "base-uri" => "'self'",
      "form-action" => "'self'"
    }

    response.headers["Content-Security-Policy"] = csp_directives.map { |k, v| "#{k} #{v}" }.join("; ")
  end

  def build_script_src
    [
      "'self'",
      "'nonce-#{request_nonce}'",
      "'sha256-ieoeWczDHkReVBsRBqaal5AFMlBtNjMzgwKvLqi/tSU='"  # Known safe inline script
    ].join(" ")
  end

  def build_style_src
    [
      "'self'",
      "'nonce-#{request_nonce}'",
      "'sha256-WAyOw4V+FqDc35lQPyRADLBWbuNK8ahvYEaQIYF1+Ps='"  # Icon controller styles
    ].join(" ")
  end

  def request_nonce
    @request_nonce ||= SecureRandom.base64(32)
  end

  helper_method :request_nonce
end
