class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Note: allow_browser is only available in Rails 8.0+
  if Rails.version.to_f >= 8.0
    allow_browser versions: :modern
  end
end
