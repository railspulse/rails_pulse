module RailsPulse
  # Turns comparisons into persisted findings.
  #
  # The dashboard's existing rules classify against absolute thresholds — a
  # route is reported because it is slow, not because it got slower — and they
  # run at render time, so nothing they conclude survives the response. This
  # runs the deterministic regression rules over every subject and writes what
  # it finds, so a finding can be trended, acknowledged, and read back later by
  # something other than the page that computed it.
  #
  # Lifecycle mirrors ExceptionGroup: identity is the thing being reported, so
  # a route that keeps regressing is one finding that keeps being seen. A
  # finding that stops being detected resolves itself; if it comes back, it
  # reopens rather than starting a second row.
  class FindingDetector
    METRICS = {
      p95:        "performance_regression",
      error_rate: "error_rate_regression"
    }.freeze

    Result = Struct.new(:detected, :opened, :reopened, :resolved, keyword_init: true)

    def self.call(as_of: Time.current)
      new(as_of: as_of).call
    end

    def initialize(as_of: Time.current)
      @as_of  = as_of
      @result = Result.new(detected: 0, opened: 0, reopened: 0, resolved: 0)
    end

    def call
      seen = []

      subject_scopes.each do |scope|
        METRICS.each do |metric, kind|
          Operations::Compare.scan(scope, metric: metric, as_of: as_of).each do |comparison|
            next unless comparison.regression?

            seen << record(comparison, kind: kind)
            @result.detected += 1
          end
        end
      end

      resolve_findings_absent_from(seen)
      @result
    end

    private

    attr_reader :as_of

    # Only scan what the host is actually tracking. Scanning jobs when job
    # tracking is off would produce findings for a table that stopped being
    # written to, which reads as a regression that nobody can act on.
    def subject_scopes
      scopes = [ RailsPulse::Route.all, RailsPulse::Query.all ]
      scopes << RailsPulse::Job.all if RailsPulse.configuration.track_jobs
      scopes
    end

    def record(comparison, kind:)
      subject = comparison.subject

      fingerprint = Finding.fingerprint_for(
        kind:         kind,
        subject_type: subject.type,
        subject_id:   subject.id,
        metric:       comparison.metric
      )

      finding = Finding.find_or_initialize_by(fingerprint: fingerprint)

      if finding.new_record?
        finding.first_detected_at = as_of
        finding.detection_count   = 0
        @result.opened += 1
      elsif finding.resolved?
        # It came back. Reopen rather than opening a second row, so the history
        # of how often this subject regresses stays on one record.
        finding.resolved_at = nil
        finding.status      = "open"
        @result.reopened += 1
      end

      change_point = locate_change_point(subject, comparison.metric)

      finding.assign_attributes(
        kind:             kind,
        subject_type:     subject.type,
        subject_id:       subject.id,
        metric:           comparison.metric.to_s,
        severity:         severity_for(comparison),
        baseline_value:   comparison.baseline_value,
        current_value:    comparison.current_value,
        delta:            comparison.delta,
        ratio:            comparison.ratio,
        baseline_count:   comparison.baseline_count,
        current_count:    comparison.current_count,
        changed_at:       change_point&.at,
        change_point_granularity: change_point&.granularity,
        last_detected_at: as_of,
        detection_count:  finding.detection_count.to_i + 1
      )

      finding.save!
      finding.fingerprint
    end

    # A regression is critical when the metric has not just moved but landed
    # somewhere the host already considers critical. That reuses the thresholds
    # the user has already tuned rather than inventing a second severity scale
    # they would have to learn.
    def severity_for(comparison)
      return "critical" if comparison.metric == :error_rate &&
        comparison.current_value >= Dashboard::Concerns::ThresholdConstants::CRITICAL_ERROR_RATE

      threshold = critical_threshold_for(comparison.subject.type)
      return "critical" if threshold && comparison.current_value >= threshold

      "warning"
    end

    def critical_threshold_for(subject_type)
      config = RailsPulse.configuration

      case subject_type
      when "RailsPulse::Route"   then config.route_thresholds[:critical]
      when "RailsPulse::Query"   then config.query_thresholds[:critical]
      when "RailsPulse::Job"     then config.job_thresholds[:critical]
      when "RailsPulse::Request" then config.request_thresholds[:critical]
      end
    end

    def locate_change_point(subject, metric)
      Operations::ChangePoint.call(subject, metric: metric)
    end

    # Anything still open that this run did not detect has stopped regressing.
    # Resolving is what keeps the findings list a description of the present
    # rather than an append-only log of everything that ever went wrong.
    def resolve_findings_absent_from(seen_fingerprints)
      stale = Finding.unresolved
      stale = stale.where.not(fingerprint: seen_fingerprints) if seen_fingerprints.any?

      @result.resolved = stale.count
      stale.find_each do |finding|
        finding.update!(status: "resolved", resolved_at: as_of)
      end
    end
  end
end
