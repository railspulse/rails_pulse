module RailsPulse
  module Seeds
    module Routes
      STANDARD_ROUTES = [
        # Standard single-verb routes
        { http_methods: '["GET"]',    path: "/",               controller_action: "home#index" },
        { http_methods: '["GET"]',    path: "/fast",            controller_action: "home#fast" },
        { http_methods: '["GET"]',    path: "/slow",            controller_action: "home#slow" },
        { http_methods: '["GET"]',    path: "/error_prone",     controller_action: "home#errors" },
        { http_methods: '["GET"]',    path: "/search",          controller_action: "home#search" },
        { http_methods: '["GET"]',    path: "/api_simple",      controller_action: "home#api_simple" },
        { http_methods: '["GET"]',    path: "/api_complex",     controller_action: "home#api_complex" },
        { http_methods: '["POST"]',   path: "/users",           controller_action: "users#create" },
        { http_methods: '["GET"]',    path: "/users/:id",       controller_action: "users#show" },
        { http_methods: '["PUT"]',    path: "/users/:id",       controller_action: "users#update" },
        { http_methods: '["DELETE"]', path: "/users/:id",       controller_action: "users#destroy" },
        { http_methods: '["POST"]',   path: "/posts",           controller_action: "posts#create" },
        { http_methods: '["GET"]',    path: "/posts/:id",       controller_action: "posts#show" },
        { http_methods: '["PUT"]',    path: "/posts/:id",       controller_action: "posts#update" },
        { http_methods: '["DELETE"]', path: "/posts/:id",       controller_action: "posts#destroy" },
        { http_methods: '["POST"]',   path: "/comments",        controller_action: "comments#create" },
        { http_methods: '["GET"]',    path: "/admin/dashboard", controller_action: "admin/dashboard#index" },
        { http_methods: '["GET"]',    path: "/admin/users",     controller_action: "admin/users#index" },
        { http_methods: '["GET"]',    path: "/api/v1/posts",    controller_action: "api/v1/posts#index" },
        { http_methods: '["GET"]',    path: "/api/v1/users",    controller_action: "api/v1/users#index" },

        # Multi-verb routes — one route record per logical endpoint, methods combined.
        { http_methods: '["GET","POST"]',   path: "/sign_in",              controller_action: "sessions#new" },
        { http_methods: '["GET","POST"]',   path: "/api/v1/search",        controller_action: "api/v1/searches#index" },
        { http_methods: '["GET","PATCH"]',  path: "/users/:id/settings",   controller_action: "users/settings#show" },

        # Routes with no controller_action — handled outside the Rails router
        # (Rack middleware, health checks, static files).
        { http_methods: '["GET"]', path: "/up",          controller_action: nil },
        { http_methods: '["GET"]', path: "/health",      controller_action: nil },
        { http_methods: '["GET"]', path: "/robots.txt",  controller_action: nil }
      ].freeze

      # Long paths for testing dashboard truncation and display handling.
      LONG_ROUTES = [
        { http_methods: '["GET"]',  path: "/rails/active_storage/representations/redirect/eyJfcmFpbHMiOnsiZGF0YSI6NDIsInB1ciI6ImJsb2JfaWQifX0=--a1b2c3d4e5f6789abcdef0123456789abcdef012/eyJfcmFpbHMiOnsiZGF0YSI6eyJjcm9wIjpbMTkyMCwxMDgwLDc2OCw0MzJdLCJyZXNpemVfdG9fbGltaXQiOls4MDAsNjAwXSwic2F2ZXIiOnsic3RyaXAiOnRydWUsImNvbXByZXNzaW9uIjo5fSwiZm9ybWF0IjoianBlZyJ9LCJwdXIiOiJ2YXJpYXRpb24ifX0=--9876543210fedcba987654321098765432109876/very_long_filename_with_lots_of_details.jpg" },
        { http_methods: '["GET"]',  path: "/api/v2/organizations/:organization_id/projects/:project_id/documents/:document_id/attachments/:attachment_id/versions/:version_id/representations/thumbnail", controller_action: "api/v2/documents#thumbnail" },
        { http_methods: '["POST"]', path: "/webhooks/integrations/third_party_service/notifications/delivery_status_updates/batch_processing/results", controller_action: "webhooks/integrations#batch_results" },
        { http_methods: '["GET"]',  path: "/rails/active_storage/disk/encoded_key/eyJfcmFpbHMiOnsiZGF0YSI6NzgsInB1ciI6ImJsb2JfaWQifX0=--xyz789abc123def456ghi789jkl012mno345pqr678/eyJfcmFpbHMiOnsiZGF0YSI6eyJ0cmFuc2Zvcm0iOnsibWV0aG9kIjoidHJhbnNmb3JtIiwid2lkdGgiOjEyMDAsImhlaWdodCI6ODAwLCJyZXNpemUiOiJmaXQiLCJmb3JtYXQiOiJwbmciLCJxdWFsaXR5Ijo4NX0sInB1ciI6InZhcmlhdGlvbiJ9fX0=--fedcba0987654321abcdef1234567890abcdef12/extremely_detailed_technical_documentation_report_final_version.pdf" },
        { http_methods: '["PUT"]',  path: "/admin/system/configuration/advanced_settings/performance_monitoring/database_optimization/query_analysis/automated_recommendations", controller_action: "admin/system/configuration#update" }
      ].freeze

      def self.seed!
        routes_data = STANDARD_ROUTES.dup
        routes_data += LONG_ROUTES if ENV["SEED_LONG_PATHS"] == "true"

        routes_data.map { |route_data| ::RailsPulse::Route.create!(route_data) }
      end
    end
  end
end
