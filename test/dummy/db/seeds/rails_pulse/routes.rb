module RailsPulse
  module Seeds
    module Routes
      STANDARD_ROUTES = [
        { method: "GET", path: "/" },
        { method: "GET", path: "/fast" },
        { method: "GET", path: "/slow" },
        { method: "GET", path: "/error_prone" },
        { method: "GET", path: "/search" },
        { method: "GET", path: "/api_simple" },
        { method: "GET", path: "/api_complex" },
        { method: "POST", path: "/users" },
        { method: "GET", path: "/users/:id" },
        { method: "PUT", path: "/users/:id" },
        { method: "DELETE", path: "/users/:id" },
        { method: "POST", path: "/posts" },
        { method: "GET", path: "/posts/:id" },
        { method: "PUT", path: "/posts/:id" },
        { method: "DELETE", path: "/posts/:id" },
        { method: "POST", path: "/comments" },
        { method: "GET", path: "/admin/dashboard" },
        { method: "GET", path: "/admin/users" },
        { method: "GET", path: "/api/v1/posts" },
        { method: "GET", path: "/api/v1/users" }
      ].freeze

      # Long paths for testing dashboard truncation and display handling
      LONG_ROUTES = [
        { method: "GET", path: "/rails/active_storage/representations/redirect/eyJfcmFpbHMiOnsiZGF0YSI6NDIsInB1ciI6ImJsb2JfaWQifX0=--a1b2c3d4e5f6789abcdef0123456789abcdef012/eyJfcmFpbHMiOnsiZGF0YSI6eyJjcm9wIjpbMTkyMCwxMDgwLDc2OCw0MzJdLCJyZXNpemVfdG9fbGltaXQiOls4MDAsNjAwXSwic2F2ZXIiOnsic3RyaXAiOnRydWUsImNvbXByZXNzaW9uIjo5fSwiZm9ybWF0IjoianBlZyJ9LCJwdXIiOiJ2YXJpYXRpb24ifX0=--9876543210fedcba987654321098765432109876/very_long_filename_with_lots_of_details.jpg" },
        { method: "GET", path: "/api/v2/organizations/:organization_id/projects/:project_id/documents/:document_id/attachments/:attachment_id/versions/:version_id/representations/thumbnail" },
        { method: "POST", path: "/webhooks/integrations/third_party_service/notifications/delivery_status_updates/batch_processing/results" },
        { method: "GET", path: "/rails/active_storage/disk/encoded_key/eyJfcmFpbHMiOnsiZGF0YSI6NzgsInB1ciI6ImJsb2JfaWQifX0=--xyz789abc123def456ghi789jkl012mno345pqr678/eyJfcmFpbHMiOnsiZGF0YSI6eyJ0cmFuc2Zvcm0iOnsibWV0aG9kIjoidHJhbnNmb3JtIiwid2lkdGgiOjEyMDAsImhlaWdodCI6ODAwLCJyZXNpemUiOiJmaXQiLCJmb3JtYXQiOiJwbmciLCJxdWFsaXR5Ijo4NX0sInB1ciI6InZhcmlhdGlvbiJ9fQ==--fedcba0987654321abcdef1234567890abcdef12/extremely_detailed_technical_documentation_report_final_version.pdf" },
        { method: "PUT", path: "/admin/system/configuration/advanced_settings/performance_monitoring/database_optimization/query_analysis/automated_recommendations" }
      ].freeze

      def self.seed!
        routes_data = STANDARD_ROUTES.dup
        routes_data += LONG_ROUTES if ENV["SEED_LONG_PATHS"] == "true"

        routes_data.map { |route_data| ::RailsPulse::Route.create!(route_data) }
      end
    end
  end
end
