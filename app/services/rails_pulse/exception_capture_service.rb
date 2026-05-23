module RailsPulse
  class ExceptionCaptureService
    APP_FRAME_PATTERN = %r{/app/|/lib/|/config/}
    GEM_FRAME_PATTERN = %r{/gems/|/rubygems/|/bundler/|/ruby/}

    PARAMS_SIZE_LIMIT = 10_240 # 10KB
    DEPLOY_SHA_TTL    = 60     # seconds

    # Cached on the class so every request in this process shares one value instead
    # of each hitting the DB. Because multiple threads can call capture concurrently,
    # the cache variables need a mutex to prevent torn reads/writes.
    @_deploy_sha_mutex     = Mutex.new # guards @_deploy_sha_value and @_deploy_sha_cached_at
    @_deploy_sha_value     = nil
    @_deploy_sha_cached_at = nil

    class << self
      def capture(exception, request_url: nil, request_method: nil, request_params: nil, environment: nil, deploy_sha: nil)
        new(exception, request_url: request_url, request_method: request_method, request_params: request_params, environment: environment, deploy_sha: deploy_sha).capture
      end

      def fetch_deploy_sha
        @_deploy_sha_mutex.synchronize do
          # Check expiry inside the lock so only one thread does the DB query when
          # the cache is cold — other threads block here and then see the fresh value.
          if @_deploy_sha_cached_at.nil? || (Time.current.to_f - @_deploy_sha_cached_at) >= DEPLOY_SHA_TTL
            @_deploy_sha_value     = RailsPulse::Deployment.order(started_at: :desc).first&.revision
            @_deploy_sha_cached_at = Time.current.to_f
          end
          @_deploy_sha_value
        end
      end

      def reset_deploy_sha_cache!
        @_deploy_sha_mutex.synchronize do
          @_deploy_sha_value     = nil
          @_deploy_sha_cached_at = nil
        end
      end
    end

    def initialize(exception, request_url: nil, request_method: nil, request_params: nil, environment: nil, deploy_sha: nil)
      @exception = exception
      @request_url = request_url
      @request_method = request_method
      @request_params = request_params
      @environment = environment || Rails.env.to_s
      @deploy_sha = deploy_sha
    end

    def capture
      return unless RailsPulse.configuration.track_exceptions
      return if RequestStore.store[:skip_recording_rails_pulse_activity]

      frames      = parse_backtrace(@exception.backtrace || [])
      fingerprint = compute_fingerprint(@exception.class.name, frames)
      now         = Time.current

      group = upsert_group(fingerprint, now)
      create_occurrence(group, frames, now)
    rescue => e
      Rails.logger.error("[RailsPulse] ExceptionCaptureService error: #{e.message}")
      nil
    end

    private

    def parse_backtrace(raw_backtrace)
      raw_backtrace.first(50).filter_map do |line|
        match = line.match(/\A(.+):(\d+):in ['`](.+?)'\z/)
        next unless match
        { file: match[1], line: match[2].to_i, method: match[3] }
      end
    end

    def first_app_frame(frames)
      frames.find { |f| f[:file].match?(APP_FRAME_PATTERN) && !f[:file].match?(GEM_FRAME_PATTERN) }
    end

    def compute_fingerprint(exception_class, frames)
      frame    = first_app_frame(frames)
      location = frame ? "#{frame[:file]}:#{frame[:line]}" : "unknown"
      Digest::SHA256.hexdigest("#{exception_class}:#{location}")
    end

    # Single SQL upsert: inserts a new group or updates the existing one.
    # occurrence_count is incremented atomically in the same statement, so no
    # separate update_counters call is needed and no race window exists.
    def upsert_group(fingerprint, now)
      message = @exception.message.to_s.truncate(500)
      conn    = ExceptionGroup.connection

      conn.execute(<<~SQL)
        INSERT INTO rails_pulse_exception_groups
          (fingerprint, exception_class, message, first_seen_at, last_seen_at, occurrence_count, created_at, updated_at)
        VALUES (
          #{conn.quote(fingerprint)},
          #{conn.quote(@exception.class.name)},
          #{conn.quote(message)},
          #{conn.quote(now)},
          #{conn.quote(now)},
          1,
          #{conn.quote(now)},
          #{conn.quote(now)}
        )
        ON CONFLICT (fingerprint) DO UPDATE SET
          exception_class  = EXCLUDED.exception_class,
          message          = EXCLUDED.message,
          last_seen_at     = EXCLUDED.last_seen_at,
          occurrence_count = rails_pulse_exception_groups.occurrence_count + 1,
          updated_at       = EXCLUDED.updated_at
      SQL

      ExceptionGroup.find_by!(fingerprint: fingerprint)
    end

    def current_deploy_sha
      self.class.fetch_deploy_sha
    end

    def filtered_params
      return nil unless RailsPulse.configuration.capture_exception_params
      return nil if @request_params.blank?

      params_hash = @request_params.respond_to?(:to_unsafe_h) ? @request_params.to_unsafe_h : @request_params.to_h
      filter      = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered    = filter.filter(params_hash)

      serialized = filtered.to_json
      serialized.bytesize <= PARAMS_SIZE_LIMIT ? filtered : nil
    end

    def create_occurrence(group, frames, now)
      ExceptionOccurrence.create!(
        exception_group: group,
        exception_class: @exception.class.name,
        message:         @exception.message.to_s.truncate(500),
        backtrace:       frames,
        request_url:     @request_url,
        request_method:  @request_method,
        request_params:  filtered_params,
        environment:     @environment,
        deploy_sha:      @deploy_sha || current_deploy_sha,
        occurred_at:     now
      )
    end
  end
end
