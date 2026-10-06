module RailsPulse
  module Cloud
    # Sends this installation's data to Rails Pulse Cloud by the sync
    # contract. `hourly` runs after SummaryJob: it queues each newly
    # summarized hour with the exception groups and deployments that changed,
    # then sends what is due. `minutely` sends the health update for the
    # minute just ended, queues deployments recorded or finished since the
    # last run, and sends what is due, which is also how retries happen.
    #
    # Batches wait in BufferedBatch until Cloud accepts them; health updates
    # are never buffered, because one that arrives late is no use. With
    # config.cloud unset nothing here runs, and no failure here is raised to
    # the caller: Cloud being down, or refusing the key, must never affect
    # the host application or local tracking.
    class Sync
      # Hours queued in one run, so catching up after an outage is spread
      # over several.
      MAX_HOURS_PER_RUN = 24
      MAX_BATCHES_PER_FLUSH = 50

      BACKOFF_START = 1.minute
      BACKOFF_MAX = 1.hour
      DEFAULT_RETRY_AFTER = 1.minute
      # After Cloud refuses the key, the plan or the application, buffering
      # continues and sending is retried this often.
      REFUSED_RETRY = 1.hour
      UNSUPPORTED_RETRY = 1.day

      DEPRECATION_HEADER = "Rails-Pulse-Contract-Deprecated".freeze

      # The hours and record windows the next hourly run would queue,
      # without queueing anything or creating the installation row.
      Plan = Struct.new(:hours, :exception_groups, :deployments, keyword_init: true)

      def initialize(settings: RailsPulse.configuration.cloud, client: nil, now: Time.current, jitter: nil)
        @settings = settings
        @client = client || Client.new(settings)
        @now = now
        @jitter = jitter || ->(delay) { delay * (0.5 + (rand / 2)) }
      end

      def enabled?
        @settings.enabled? && tables_available?
      end

      def hourly
        guarded("hourly sync") do
          plan = plan_for(installation)
          route_patterns = RoutePattern.new
          plan.hours.each do |hour|
            items = SummaryItems.new(hour, adapter: envelope[:database_adapter], route_patterns: route_patterns).items
            queue(items) { installation.update!(last_hour_sent_at: hour) }
          end
          queue_records(plan, exception_groups: true)
          flush
        end
      end

      def minutely
        guarded("health update") do
          send_health
          queue_records(plan_for(installation), exception_groups: false)
          flush
        end
      end

      # What the next hourly run would queue for `record`, which may be nil
      # before the first sync.
      def plan_for(record)
        Plan.new(hours: unsent_hours(record&.last_hour_sent_at),
                 exception_groups: window_since(record&.exception_groups_sent_through),
                 deployments: window_since(record&.deployments_sent_through))
      end

      def envelope
        @envelope ||= Batch.envelope(application: @settings.application, environment: @settings.environment,
                                     installation_id: installation.installation_id)
      end

      private

      def installation
        @installation ||= Installation.current
      end

      def guarded(what)
        return :disabled unless enabled?

        yield
        :ok
      rescue StandardError => e
        RailsPulse.logger.error("Rails Pulse Cloud #{what} failed: #{e.class} - #{e.message}")
        record_failure("#{what} failed: #{e.class}: #{e.message}")
        :failed
      end

      # The failure is already logged; if the database is what failed, it
      # cannot be recorded there too.
      def record_failure(message)
        installation.record_error!(message, now: @now)
      rescue StandardError
        nil
      end

      def tables_available?
        Installation.table_exists? && BufferedBatch.table_exists?
      rescue ActiveRecord::ActiveRecordError
        false
      end

      # -- Queueing ------------------------------------------------------

      # Summarized hours after the last one queued, oldest first. The first
      # sync starts at the latest hour rather than replaying history.
      def unsent_hours(last_sent)
        heartbeats = Summary.overall_requests.for_period_type("hour")
        latest = heartbeats.maximum(:period_start)
        return [] unless latest

        from = last_sent ? last_sent + 1.second : latest
        heartbeats.where(period_start: from..latest).order(:period_start).limit(MAX_HOURS_PER_RUN)
          .pluck(:period_start).map(&:in_time_zone)
      end

      # Rows changed since the cursor and before now. The first sync covers
      # the hourly summary retention, so Cloud can name what those hours count.
      def window_since(cursor)
        (cursor || (@now - RailsPulse.configuration.hourly_summary_retention))...@now
      end

      def queue_records(plan, exception_groups:)
        items = []
        items += RecordItems.exception_groups_updated(plan.exception_groups) if exception_groups
        items += RecordItems.deployments_updated(plan.deployments)
        cursors = { deployments_sent_through: plan.deployments.end }
        cursors[:exception_groups_sent_through] = plan.exception_groups.end if exception_groups
        queue(items) { installation.update!(cursors) }
      end

      # Batches the items into the buffer and moves the cursor in the same
      # transaction, so a crash between the two neither loses nor repeats them.
      def queue(items)
        RailsPulse::ApplicationRecord.transaction do
          Batch.build(items, envelope: envelope).each { |batch| BufferedBatch.enqueue!(batch, now: @now) }
          yield
        end
        dropped = BufferedBatch.prune!(@now)
        RailsPulse.logger.warn("Rails Pulse Cloud buffer full: dropped #{dropped} oldest batch(es)") if dropped.positive?
      end

      # -- Sending -------------------------------------------------------

      def flush
        return if installation.paused?(@now)

        # Read one at a time: a split adds batches that are due at once.
        MAX_BATCHES_PER_FLUSH.times do
          buffered = BufferedBatch.due(@now).first
          break unless buffered && deliver(buffered) == :continue
        end
      end

      def deliver(buffered)
        contents = buffered.contents.merge("sent_at" => @now.utc.iso8601)
        response = @client.post(contents.to_json)

        case outcome(response)
        when :accepted
          buffered.destroy!
          installation.record_success!(deprecated_on: response.header(DEPRECATION_HEADER), now: @now)
          :continue
        when :malformed
          buffered.destroy!
          RailsPulse.logger.error("Rails Pulse Cloud refused batch #{buffered.batch_id} as malformed: #{response.body}")
          installation.record_error!("Cloud refused a batch as malformed and it was dropped: #{response.message}", now: @now)
          :continue
        when :too_large
          split(buffered, contents)
          :continue
        when :rate_limited
          retry_after = response.header("Retry-After").to_i
          buffered.update!(next_attempt_at: @now + (retry_after.positive? ? retry_after : DEFAULT_RETRY_AFTER),
                           last_error: response.message)
          :stop
        when :refused, :unsupported
          pause(response)
          :stop
        else
          back_off(buffered, response.message)
          :stop
        end
      rescue Client::Unavailable => e
        back_off(buffered, e.message)
        :stop
      end

      def send_health
        return if installation.paused?(@now)

        batch = Batch.new([ HealthItem.for_minute_before(@now) ], envelope: envelope, sent_at: @now)
        response = @client.post(batch.to_json)
        case outcome(response)
        when :accepted
          installation.record_success!(deprecated_on: response.header(DEPRECATION_HEADER), now: @now)
          installation.update!(last_health_at: @now)
        when :refused, :unsupported
          pause(response)
        else
          installation.record_error!("Health update not sent: #{response.message}", now: @now)
        end
      rescue Client::Unavailable => e
        installation.record_error!("Health update not sent: #{e.message}", now: @now)
      end

      def outcome(response)
        case response.status
        when 202 then :accepted
        when 200 then :accepted
        when 400 then :malformed
        when 401, 402, 404 then :refused
        when 413 then :too_large
        when 422 then :unsupported
        when 429 then :rate_limited
        else :unavailable
        end
      end

      def pause(response)
        if response.status == 422
          installation.pause!(@now + UNSUPPORTED_RETRY,
                              "Rails Pulse Cloud does not accept this gem's contract version (#{response.message}). Upgrade the rails_pulse gem.",
                              now: @now)
        else
          installation.pause!(@now + REFUSED_RETRY, "#{refusal(response.status)}: #{response.message}", now: @now)
        end
      end

      def refusal(status)
        case status
        when 401 then "Rails Pulse Cloud refused config.cloud.api_key"
        when 402 then "The Rails Pulse Cloud subscription is not active"
        else "Rails Pulse Cloud does not know the application #{@settings.application.inspect}"
        end
      end

      # 1 minute, doubling, up to an hour, with jitter so installations that
      # failed together do not retry together.
      def back_off(buffered, message)
        attempts = buffered.attempts + 1
        delay = [ BACKOFF_START * (2**(attempts - 1)), BACKOFF_MAX ].min
        buffered.update!(attempts: attempts, next_attempt_at: @now + @jitter.call(delay.to_f).seconds, last_error: message)
        installation.record_error!("Cloud unavailable, retrying: #{message}", now: @now)
      end

      # Halves a batch Cloud found too large. Each half is a new batch with
      # its own id: it carries different items, so it is not a resend.
      def split(buffered, contents)
        items = contents["items"]
        if items.size <= 1
          buffered.destroy!
          installation.record_error!("Cloud refused a single item as too large and it was dropped", now: @now)
          return
        end

        envelope = contents.except("batch_id", "sent_at", "items").transform_keys(&:to_sym)
        RailsPulse::ApplicationRecord.transaction do
          items.each_slice((items.size / 2.0).ceil) do |half|
            BufferedBatch.enqueue!(Batch.new(half, envelope: envelope), now: @now)
          end
          buffered.destroy!
        end
      end
    end
  end
end
