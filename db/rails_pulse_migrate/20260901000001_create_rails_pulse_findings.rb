class CreateRailsPulseFindings < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:rails_pulse_findings)
      create_table :rails_pulse_findings do |t|
        t.string   :fingerprint,  null: false, comment: "SHA256 of kind + subject + metric — stable identity across detection runs"
        t.string   :kind,         null: false, comment: "What was detected, e.g. performance_regression"
        t.string   :subject_type, null: false, comment: "RailsPulse::Route, RailsPulse::Query, RailsPulse::Job or RailsPulse::Request"
        t.bigint   :subject_id,   null: false, comment: "Id of the subject; 0 for the overall request rollup"
        t.string   :metric,       null: false, comment: "p50, p95, p99, avg or error_rate"
        t.string   :severity,     null: false, comment: "warning or critical"
        t.string   :status,       null: false, default: "open", comment: "open, acknowledged or resolved"
        t.float    :baseline_value, comment: "Traffic-weighted metric across the baseline window"
        t.float    :current_value,  comment: "Metric across the window under test"
        t.float    :delta,          comment: "current_value - baseline_value"
        t.float    :ratio,          comment: "current_value / baseline_value"
        t.integer  :baseline_count, comment: "Observations behind the baseline"
        t.integer  :current_count,  comment: "Observations behind the current window"
        t.datetime :changed_at,     comment: "Estimated change point, when one could be located"
        t.string   :change_point_granularity, comment: "hour or day — the precision of changed_at"
        t.datetime :first_detected_at, null: false, comment: "When this finding was first raised"
        t.datetime :last_detected_at,  null: false, comment: "Most recent detection run that still saw it"
        t.datetime :resolved_at,       comment: "When the finding last stopped being detected"
        t.integer  :detection_count,   null: false, default: 0, comment: "Number of runs that have seen this finding"
        t.timestamps
      end
    end

    unless index_exists?(:rails_pulse_findings, :fingerprint, name: "index_rails_pulse_findings_on_fingerprint")
      add_index :rails_pulse_findings, :fingerprint, unique: true, name: "index_rails_pulse_findings_on_fingerprint"
    end

    unless index_exists?(:rails_pulse_findings, :status, name: "index_rails_pulse_findings_on_status")
      add_index :rails_pulse_findings, :status, name: "index_rails_pulse_findings_on_status"
    end

    unless index_exists?(:rails_pulse_findings, :last_detected_at, name: "index_rails_pulse_findings_on_last_detected_at")
      add_index :rails_pulse_findings, :last_detected_at, name: "index_rails_pulse_findings_on_last_detected_at"
    end

    unless index_exists?(:rails_pulse_findings, [ :subject_type, :subject_id ], name: "index_rails_pulse_findings_on_subject")
      add_index :rails_pulse_findings, [ :subject_type, :subject_id ], name: "index_rails_pulse_findings_on_subject"
    end
  end
end
