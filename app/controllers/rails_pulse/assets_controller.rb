module RailsPulse
  class AssetsController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [ :show ]

    def show
      asset_name = params[:asset_name]
      asset_path = Rails.root.join("public", "rails-pulse-assets", asset_name)

      # Fallback to engine assets if not found in host app
      unless File.exist?(asset_path)
        asset_path = RailsPulse::Engine.root.join("public", "rails-pulse-assets", asset_name)
      end

      if File.exist?(asset_path)
        content_type = case File.extname(asset_name)
        when ".js" then "application/javascript"
        when ".css" then "text/css"
        when ".map" then "application/json"
        when ".svg" then "image/svg+xml"
        else "application/octet-stream"
        end

        send_file asset_path,
                  type: content_type,
                  disposition: "inline",
                  cache: true,
                  expires: 1.year.from_now
      else
        head :not_found
      end
    end
  end
end
