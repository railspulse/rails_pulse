require "json"

module RailsPulse
  module Cloud
    # What `rails rails_pulse:cloud:preview` prints: the batches the next
    # hourly sync would queue, and the health update for the minute just
    # ended. It reads the same plan and builds items with the same code as
    # Sync, so the preview cannot drift from what is sent, and it writes
    # nothing: no installation row, no buffered batch, no request.
    class Preview
      METADATA_NOTICE = "Deployment metadata is sent as recorded: everything your deploy script puts in it goes to Rails Pulse Cloud.".freeze

      def initialize(settings: RailsPulse.configuration.cloud, now: Time.current)
        @settings = settings
        @now = now
        @installation = Installation.table_exists? ? Installation.existing : nil
      rescue ActiveRecord::ActiveRecordError
        @installation = nil
      end

      def plan
        @plan ||= Sync.new(settings: @settings, now: @now).plan_for(@installation)
      end

      def batches
        route_patterns = RoutePattern.new
        items = plan.hours.flat_map do |hour|
          SummaryItems.new(hour, adapter: envelope[:database_adapter], route_patterns: route_patterns).items
        end
        items += RecordItems.exception_groups_updated(plan.exception_groups)
        items += RecordItems.deployments_updated(plan.deployments)
        Batch.build(items, envelope: envelope)
      end

      def health_batch
        Batch.new([ HealthItem.for_minute_before(@now) ], envelope: envelope, sent_at: @now)
      end

      def render
        lines = [ "Rails Pulse Cloud preview", "" ]
        lines << status_line
        lines << "Installation ID: assigned on the first sync" if @installation.nil?
        lines << ""

        built = batches
        if plan.hours.empty?
          lines << "No newly summarized hour to send. Is SummaryJob scheduled?"
        else
          lines << "Next hourly sync: #{plan.hours.map { |hour| hour.utc.iso8601 }.join(', ')}."
        end
        lines << "#{pluralize(built.sum { |batch| batch.items.size }, 'item')} in #{pluralize(built.size, 'batch')}."
        lines << METADATA_NOTICE
        lines << ""
        built.each { |batch| lines << JSON.pretty_generate(batch.to_h) }

        lines << ""
        lines << "Health update for the minute just ended, sent every minute and never buffered:"
        lines << JSON.pretty_generate(health_batch.to_h)
        lines.join("\n") + "\n"
      end

      private

      def envelope
        @envelope ||= Batch.envelope(application: @settings.application, environment: @settings.environment,
                                     installation_id: @installation&.installation_id)
      end

      def status_line
        if @settings.enabled?
          "Sending to #{@settings.url} as #{@settings.application} (#{@settings.environment})."
        else
          "Not sending: set config.cloud.api_key and config.cloud.application to turn Rails Pulse Cloud on. " \
            "Until then no network calls are made."
        end
      end

      def pluralize(count, word)
        "#{count} #{count == 1 ? word : word.pluralize}"
      end
    end
  end
end
