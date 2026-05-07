module RailsPulse
  class ExceptionCaptureService
    APP_FRAME_PATTERN = %r{/app/}
    GEM_FRAME_PATTERN = %r{/gems/|/rubygems/|/bundler/|/ruby/}

    PARAMS_SIZE_LIMIT = 10_240 # 10KB

    def self.capture(exception, request_url: nil, request_method: nil, request_params: nil, environment: nil, deploy_sha: nil)
      new(exception, request_url: request_url, request_method: request_method, request_params: request_params, environment: environment, deploy_sha: deploy_sha).capture
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

      frames = parse_backtrace(@exception.backtrace || [])
      fingerprint = compute_fingerprint(@exception.class.name, frames)
      now = Time.current

      group = upsert_group(fingerprint, now)
      create_occurrence(group, frames, now)
    rescue => e
      Rails.logger.error("[RailsPulse] ExceptionCaptureService error: #{e.message}")
      nil
    end

    private

    def parse_backtrace(raw_backtrace)
      raw_backtrace.first(50).filter_map do |line|
        match = line.match(/\A(.+):(\d+):in ['`](.+)'?\z/)
        next unless match
        { file: match[1], line: match[2].to_i, method: match[3] }
      end
    end

    def first_app_frame(frames)
      frames.find { |f| f[:file].match?(APP_FRAME_PATTERN) && !f[:file].match?(GEM_FRAME_PATTERN) }
    end

    def compute_fingerprint(exception_class, frames)
      frame = first_app_frame(frames)
      location = frame ? "#{frame[:file]}:#{frame[:line]}" : "unknown"
      Digest::SHA256.hexdigest("#{exception_class}:#{location}")
    end

    def upsert_group(fingerprint, now)
      group = ExceptionGroup.find_or_initialize_by(fingerprint: fingerprint)
      group.exception_class  = @exception.class.name
      group.message          = @exception.message.to_s.truncate(500)
      group.first_seen_at  ||= now
      group.last_seen_at     = now
      group.save!

      ExceptionGroup.where(id: group.id).update_counters(occurrence_count: 1)
      group.reload
    rescue ActiveRecord::RecordNotUnique
      group = ExceptionGroup.find_by!(fingerprint: fingerprint)
      ExceptionGroup.where(id: group.id).update_counters(occurrence_count: 1)
      group.reload
    end

    def current_deploy_sha
      @current_deploy_sha ||= RailsPulse::Deployment.order(started_at: :desc).first&.revision
    end

    def filtered_params
      return nil unless RailsPulse.configuration.capture_exception_params
      return nil if @request_params.blank?

      params_hash = @request_params.respond_to?(:to_unsafe_h) ? @request_params.to_unsafe_h : @request_params.to_h
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter(params_hash)

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
