require "digest"

module RailsPulse
  module Seeds
    module Exceptions
      EXCEPTION_DEFINITIONS = [
        {
          exception_class: "ActiveRecord::RecordNotFound",
          app_frame: { file: "app/controllers/posts_controller.rb", line: 12, method: "show" },
          messages: [
            "Couldn't find Post with 'id'=1099",
            "Couldn't find Post with 'id'=2847",
            "Couldn't find Post with 'id'=9001"
          ],
          backtrace: [
            { file: "app/controllers/posts_controller.rb", line: 12, method: "show" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/posts/%d",
          request_method: "GET",
          occurrence_weight: 0.30
        },
        {
          exception_class: "ActiveRecord::RecordNotFound",
          app_frame: { file: "app/controllers/comments_controller.rb", line: 8, method: "destroy" },
          messages: [
            "Couldn't find Comment with 'id'=4411",
            "Couldn't find Comment with 'id'=8823"
          ],
          backtrace: [
            { file: "app/controllers/comments_controller.rb", line: 8, method: "destroy" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/comments/%d",
          request_method: "DELETE",
          occurrence_weight: 0.08
        },
        {
          exception_class: "ActionController::ParameterMissing",
          app_frame: { file: "app/controllers/users_controller.rb", line: 47, method: "user_params" },
          messages: [
            "param is missing or the value is empty: user",
            "param is missing or the value is empty: email"
          ],
          backtrace: [
            { file: "app/controllers/users_controller.rb", line: 47, method: "user_params" },
            { file: "app/controllers/users_controller.rb", line: 22, method: "create" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/users",
          request_method: "POST",
          occurrence_weight: 0.12
        },
        {
          exception_class: "Net::ReadTimeout",
          app_frame: { file: "app/services/payment_service.rb", line: 34, method: "charge" },
          messages: [
            "Net::ReadTimeout with #<TCPSocket:(closed)>",
            "execution expired"
          ],
          backtrace: [
            { file: "app/services/payment_service.rb", line: 34, method: "charge" },
            { file: "app/controllers/orders_controller.rb", line: 19, method: "create" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/orders",
          request_method: "POST",
          occurrence_weight: 0.06
        },
        {
          exception_class: "NoMethodError",
          app_frame: { file: "app/models/user.rb", line: 58, method: "full_name" },
          messages: [
            "undefined method 'full_name' for nil",
            "undefined method 'email' for nil:NilClass"
          ],
          backtrace: [
            { file: "app/models/user.rb", line: 58, method: "full_name" },
            { file: "app/controllers/profiles_controller.rb", line: 14, method: "show" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/profile",
          request_method: "GET",
          occurrence_weight: 0.10
        },
        {
          exception_class: "ActiveRecord::RecordInvalid",
          app_frame: { file: "app/models/post.rb", line: 23, method: "create!" },
          messages: [
            "Validation failed: Title can't be blank",
            "Validation failed: Title can't be blank, Body can't be blank",
            "Validation failed: Title is too long (maximum is 255 characters)"
          ],
          backtrace: [
            { file: "app/models/post.rb", line: 23, method: "create!" },
            { file: "app/controllers/posts_controller.rb", line: 31, method: "create" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/posts",
          request_method: "POST",
          occurrence_weight: 0.14
        },
        {
          exception_class: "JSON::ParserError",
          app_frame: { file: "app/controllers/api/v1/webhooks_controller.rb", line: 11, method: "receive" },
          messages: [
            "765: unexpected token at 'undefined'",
            "unexpected character (after ) at line 1, column 1"
          ],
          backtrace: [
            { file: "app/controllers/api/v1/webhooks_controller.rb", line: 11, method: "receive" },
            { file: "app/controllers/application_controller.rb", line: 8, method: "call" }
          ],
          request_url_template: "/api/v1/webhooks",
          request_method: "POST",
          occurrence_weight: 0.05
        },
        {
          exception_class: "ArgumentError",
          app_frame: { file: "app/jobs/report_generator_job.rb", line: 18, method: "perform" },
          messages: [
            "Invalid date range: start_date must be before end_date",
            "wrong number of arguments (given 0, expected 1)"
          ],
          backtrace: [
            { file: "app/jobs/report_generator_job.rb", line: 18, method: "perform" },
            { file: "app/jobs/application_job.rb", line: 5, method: "perform_now" }
          ],
          request_url_template: nil,
          request_method: nil,
          occurrence_weight: 0.07
        },
        {
          exception_class: "Errno::ECONNREFUSED",
          app_frame: { file: "app/services/notification_service.rb", line: 27, method: "deliver" },
          messages: [
            "Connection refused - connect(2) for \"smtp.example.com\" port 587",
            "Connection refused - connect(2) for \"127.0.0.1\" port 6379"
          ],
          backtrace: [
            { file: "app/services/notification_service.rb", line: 27, method: "deliver" },
            { file: "app/jobs/notification_job.rb", line: 9, method: "perform" },
            { file: "app/jobs/application_job.rb", line: 5, method: "perform_now" }
          ],
          request_url_template: nil,
          request_method: nil,
          occurrence_weight: 0.08
        }
      ].freeze

      def self.seed!(deploy_shas: [])
        print "Generating exception groups and occurrences"

        total_occurrences = 0
        groups = EXCEPTION_DEFINITIONS.map do |defn|
          fingerprint = compute_fingerprint(defn[:exception_class], defn[:app_frame])
          first_seen = rand(7..SeedConfig.days_ago).days.ago - rand(0..3600).seconds

          group = ::RailsPulse::ExceptionGroup.create!(
            fingerprint: fingerprint,
            exception_class: defn[:exception_class],
            message: defn[:messages].last,
            first_seen_at: first_seen,
            last_seen_at: first_seen,
            occurrence_count: 0
          )

          count = create_occurrences(group, defn, first_seen, deploy_shas)
          total_occurrences += count

          group.update!(
            occurrence_count: count,
            last_seen_at: ::RailsPulse::ExceptionOccurrence.where(exception_group: group).maximum(:occurred_at) || first_seen,
            message: defn[:messages].last
          )

          print "."
          group
        end

        puts "\nCreated #{groups.count} exception groups with #{total_occurrences} occurrences"
        groups
      end

      private

      def self.compute_fingerprint(exception_class, frame)
        location = "#{frame[:file]}:#{frame[:line]}"
        Digest::SHA256.hexdigest("#{exception_class}:#{location}")
      end

      def self.create_occurrences(group, defn, first_seen, deploy_shas)
        base_count = (SeedConfig.days_ago * defn[:occurrence_weight] * rand(2.0..4.0)).ceil
        count = [ base_count, 1 ].max

        count.times do |i|
          fraction = i.to_f / count
          occurred_at = first_seen + (fraction * (SeedConfig.days_ago.days - 1.hour)).to_i.seconds + rand(0..3600).seconds
          occurred_at = [ occurred_at, Time.current - 2.minutes ].min

          message = defn[:messages].sample
          url = defn[:request_url_template] ? format(defn[:request_url_template], rand(100..9999)) : nil
          params = build_params(defn, url)
          sha = deploy_shas.any? ? deploy_shas.sample : nil

          ::RailsPulse::ExceptionOccurrence.create!(
            exception_group: group,
            exception_class: defn[:exception_class],
            message: message,
            backtrace: defn[:backtrace],
            request_url: url,
            request_method: defn[:request_method],
            request_params: params,
            environment: "production",
            deploy_sha: sha,
            occurred_at: occurred_at
          )
        end

        count
      end

      def self.build_params(defn, url)
        return nil unless url

        case defn[:exception_class]
        when "ActiveRecord::RecordNotFound"
          id = url.split("/").last
          { "controller" => url.split("/")[-2], "action" => action_for(defn[:request_method]), "id" => id }
        when "ActionController::ParameterMissing"
          { "controller" => "users", "action" => "create" }
        when "ActiveRecord::RecordInvalid"
          { "controller" => "posts", "action" => "create", "post" => { "title" => "" } }
        when "JSON::ParserError"
          nil
        else
          nil
        end
      end

      def self.action_for(method)
        case method
        when "GET"    then "show"
        when "POST"   then "create"
        when "DELETE" then "destroy"
        when "PATCH", "PUT" then "update"
        else "index"
        end
      end
    end
  end
end
