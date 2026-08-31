module RailsPulse
  module FindingsHelper
    # Findings point at four different kinds of subject, and the overall request
    # rollup points at none. Keeping the mapping here stops each view growing
    # its own case statement.
    def finding_subject_path(finding)
      case finding.subject_type
      when "RailsPulse::Route"          then route_path(finding.subject_id)
      when "RailsPulse::Query"          then query_path(finding.subject_id)
      when "RailsPulse::Job"            then job_path(finding.subject_id)
      when "RailsPulse::ExceptionGroup" then exception_path(finding.subject_id)
      end
    end

    def finding_metric_label(finding)
      case finding.metric
      when "error_rate" then "Error rate"
      when "volume"     then "Frequency"
      else finding.metric.upcase
      end
    end

    # "220ms → 1420ms" split into its two halves for display.
    def finding_baseline_display(finding)
      finding.to_s.split(": ", 2).last.to_s.split(" → ").first
    end

    def finding_current_display(finding)
      finding.to_s.split(" → ").last
    end
  end
end
