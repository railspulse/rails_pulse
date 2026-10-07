require "json"

module RailsPulse
  module Cloud
    # What `rails rails_pulse:cloud:preview` prints: the batches for the most
    # recent hour SummaryJob has written, with the exception groups and
    # deployments that changed since that hour began, and the health update
    # for the minute just ended. Built by the same code that builds what is
    # sent, so the preview cannot drift from it.
    class Preview
      METADATA_NOTICE = "Deployment metadata is sent as recorded: everything your deploy script puts in it goes to Rails Pulse Cloud.".freeze

      def initialize(settings: RailsPulse.configuration.cloud, installation_id: nil, now: Time.current)
        @settings = settings
        @installation_id = installation_id
        @now = now
      end

      # The latest hour with a summary heartbeat, or nil when SummaryJob has
      # not written one yet.
      def hour
        return @hour if defined?(@hour)

        @hour = Summary.overall_requests.for_period_type("hour").maximum(:period_start)&.in_time_zone
      end

      def batches
        return [] unless hour

        items = SummaryItems.new(hour, adapter: envelope[:database_adapter]).items + RecordItems.changed_since(hour)
        Batch.build(items, envelope: envelope)
      end

      def health_batch
        Batch.new([ HealthItem.for_minute_before(@now) ], envelope: envelope)
      end

      def render
        lines = [ "Rails Pulse Cloud preview", "" ]
        lines << status_line
        lines << "Installation ID: assigned on the first sync" if @installation_id.nil?
        lines << ""

        if hour
          built = batches
          lines << "Hourly sync for #{hour.utc.iso8601}: #{pluralize(built.sum { |batch| batch.items.size }, 'item')} in #{pluralize(built.size, 'batch')}."
          lines << METADATA_NOTICE
          lines << ""
          built.each { |batch| lines << JSON.pretty_generate(batch.to_h) }
        else
          lines << "No hour has been summarized yet, so there is no hourly batch to send. Is SummaryJob scheduled?"
        end

        lines << ""
        lines << "Health update for the minute just ended, sent every minute and never buffered:"
        lines << JSON.pretty_generate(health_batch.to_h)
        lines.join("\n") + "\n"
      end

      private

      def envelope
        @envelope ||= Batch.envelope(application: @settings.application, environment: @settings.environment, installation_id: @installation_id)
      end

      def status_line
        if @settings.enabled?
          "Configured to send to #{@settings.url} as #{@settings.application} (#{@settings.environment})."
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
