module RailsPulse
  module Subscribers
    class OperationSubscriber
      def self.subscribe!
        # Helper method to clean SQL labels by removing Rails comments
        def self.clean_sql_label(sql)
          return sql unless sql
          # Remove Rails SQL comments like /*action='search',application='Dummy',controller='home'*/
          sql.gsub(/\/\*[^*]*\*\//, "").strip
        end

        # Helper method to convert absolute paths to relative paths
        def self.relative_path(absolute_path)
          return absolute_path unless absolute_path&.start_with?("/")

          rails_root = Rails.root.to_s
          if absolute_path.start_with?(rails_root)
            absolute_path.sub(rails_root + "/", "")
          else
            absolute_path
          end
        end

        # Helper method to find the first app frame in the call stack
        def self.find_app_frame
          app_path = Rails.root.join("app").to_s
          caller_locations.each do |loc|
            path = loc.absolute_path || loc.path
            return path if path && path.start_with?(app_path)
          end
          nil
        end

        # Helper method to resolve controller action source location
        def self.controller_action_source_location(payload)
          return nil unless payload[:controller] && payload[:action]
          begin
            controller_klass = payload[:controller].constantize
            if controller_klass.instance_methods(false).include?(payload[:action].to_sym)
              file, line = controller_klass.instance_method(payload[:action]).source_location
              return "#{relative_path(file)}:#{line}" if file && line
            end
            # fallback: try superclass (for ApplicationController actions)
            if controller_klass.superclass.respond_to?(:instance_method)
              if controller_klass.superclass.instance_methods(false).include?(payload[:action].to_sym)
                file, line = controller_klass.superclass.instance_method(payload[:action]).source_location
                return "#{relative_path(file)}:#{line}" if file && line
              end
            end
          rescue => e
            Rails.logger.debug "[RailsPulse] Could not resolve controller source location: #{e.class} - #{e.message}"
          end
          nil
        end

        # Helper method to capture operation data
        def self.capture_operation(event_name, start, finish, payload, operation_type, label_key = nil)
          return unless RailsPulse.configuration.enabled
          return if RequestStore.store[:skip_recording_rails_pulse_activity]

          request_id = RequestStore.store[:rails_pulse_request_id]
          job_run_id = RequestStore.store[:rails_pulse_job_run_id]
          return unless request_id || job_run_id

          # Skip RailsPulse-related operations to prevent recursion
          if operation_type == "sql"
            sql = payload[:sql]
            return if sql&.include?("rails_pulse_")
          end

          label = case label_key
          when :sql then clean_sql_label(payload[:sql])
          when :template then relative_path(payload[:identifier] || payload[:template])
          when :partial then relative_path(payload[:identifier] || payload[:partial])
          when :controller then "#{payload[:controller]}##{payload[:action]}"
          when :cache then payload[:key]
          else payload[label_key] || event_name
          end

          codebase_location =
            if payload[:identifier]
              relative_path(payload[:identifier])
            elsif payload[:template]
              relative_path(payload[:template])
            elsif operation_type == "controller"
              controller_action_source_location(payload) || find_app_frame || caller_locations(3, 1).first&.path
            elsif operation_type == "sql"
              relative_path(find_app_frame || caller_locations(3, 1).first&.path)
            else
              find_app_frame || caller_locations(3, 1).first&.path
            end

          operation_data = {
            request_id: request_id,
            job_run_id: job_run_id,
            operation_type: operation_type,
            label: label,
            duration: (finish - start) * 1000,
            codebase_location: codebase_location,
            start_time: start.to_f,
            occurred_at: Time.zone.at(start)
          }

          RequestStore.store[:rails_pulse_operations] ||= []
          RequestStore.store[:rails_pulse_operations] << operation_data
        end

        # SQL queries
        ActiveSupport::Notifications.subscribe "sql.active_record" do |name, start, finish, id, payload|
          begin
            next if payload[:name] == "SCHEMA"
            capture_operation(name, start, finish, payload, "sql", :sql)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in SQL subscriber: #{e.class} - #{e.message}"
          end
        end

        # Controller action processing
        ActiveSupport::Notifications.subscribe "process_action.action_controller" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "controller", :controller)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in controller subscriber: #{e.class} - #{e.message}"
          end
        end

        # Template rendering
        ActiveSupport::Notifications.subscribe "render_template.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "template", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in template subscriber: #{e.class} - #{e.message}"
          end
        end

        # Partial rendering
        ActiveSupport::Notifications.subscribe "render_partial.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "partial", :partial)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in partial subscriber: #{e.class} - #{e.message}"
          end
        end

        # Layout rendering
        ActiveSupport::Notifications.subscribe "render_layout.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "layout", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in layout subscriber: #{e.class} - #{e.message}"
          end
        end

        # Cache operations
        ActiveSupport::Notifications.subscribe "cache_read.active_support" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "cache_read", :cache)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in cache_read subscriber: #{e.class} - #{e.message}"
          end
        end

        ActiveSupport::Notifications.subscribe "cache_write.active_support" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "cache_write", :cache)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in cache_write subscriber: #{e.class} - #{e.message}"
          end
        end

        # HTTP client requests (if using Net::HTTP)
        ActiveSupport::Notifications.subscribe "request.net_http" do |name, start, finish, id, payload|
          begin
            next unless RailsPulse.configuration.enabled
            label = "#{payload[:method]} #{payload[:uri]}"
            codebase_location = find_app_frame || caller_locations(2, 1).first&.path
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              job_run_id: RequestStore.store[:rails_pulse_job_run_id],
              operation_type: "http",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: codebase_location,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start)
            }

            if operation_data[:request_id] || operation_data[:job_run_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in HTTP subscriber: #{e.class} - #{e.message}"
          end
        end

        # Active Job processing
        ActiveSupport::Notifications.subscribe "perform.active_job" do |name, start, finish, id, payload|
          begin
            next unless RailsPulse.configuration.enabled
            label = "#{payload[:job].class.name}"
            codebase_location = find_app_frame || caller_locations(2, 1).first&.path
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              job_run_id: RequestStore.store[:rails_pulse_job_run_id],
              operation_type: "job",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: codebase_location,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start)
            }

            if operation_data[:request_id] || operation_data[:job_run_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in job subscriber: #{e.class} - #{e.message}"
          end
        end

        # Collection rendering (for rendering collections)
        ActiveSupport::Notifications.subscribe "render_collection.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "collection", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in collection subscriber: #{e.class} - #{e.message}"
          end
        end

        # Action Mailer
        ActiveSupport::Notifications.subscribe "deliver.action_mailer" do |name, start, finish, id, payload|
          begin
            next unless RailsPulse.configuration.enabled
            label = "#{payload[:mailer]}##{payload[:action]}"
            codebase_location = find_app_frame || caller_locations(2, 1).first&.path
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              job_run_id: RequestStore.store[:rails_pulse_job_run_id],
              operation_type: "mailer",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: codebase_location,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start)
            }

            if operation_data[:request_id] || operation_data[:job_run_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in mailer subscriber: #{e.class} - #{e.message}"
          end
        end

        # Active Storage
        ActiveSupport::Notifications.subscribe "service_upload.active_storage" do |name, start, finish, id, payload|
          begin
            next unless RailsPulse.configuration.enabled
            label = "Upload: #{payload[:key]}"
            codebase_location = find_app_frame || caller_locations(2, 1).first&.path
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              job_run_id: RequestStore.store[:rails_pulse_job_run_id],
              operation_type: "storage",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: codebase_location,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start)
            }

            if operation_data[:request_id] || operation_data[:job_run_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in storage subscriber: #{e.class} - #{e.message}"
          end
        end
      end
    end
  end
end
