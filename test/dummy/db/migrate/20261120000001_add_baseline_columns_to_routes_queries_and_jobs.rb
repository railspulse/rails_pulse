class AddBaselineColumnsToRoutesQueriesAndJobs < ActiveRecord::Migration[7.0]
  def change
    if table_exists?(:rails_pulse_routes)
      unless column_exists?(:rails_pulse_routes, :baseline_p50_duration)
        add_column :rails_pulse_routes, :baseline_p50_duration, :decimal, precision: 15, scale: 6, comment: "Baseline median duration in milliseconds: traffic-weighted over config.baseline_window of day summaries"
      end
      unless column_exists?(:rails_pulse_routes, :baseline_p90_duration)
        add_column :rails_pulse_routes, :baseline_p90_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 90th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_routes, :baseline_p95_duration)
        add_column :rails_pulse_routes, :baseline_p95_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 95th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_routes, :baseline_sample_count)
        add_column :rails_pulse_routes, :baseline_sample_count, :bigint, null: false, default: 0, comment: "Requests the baseline was built from"
      end
      unless column_exists?(:rails_pulse_routes, :baseline_periods)
        add_column :rails_pulse_routes, :baseline_periods, :integer, null: false, default: 0, comment: "Day summaries the baseline was built from"
      end
      unless column_exists?(:rails_pulse_routes, :baseline_computed_at)
        add_column :rails_pulse_routes, :baseline_computed_at, :datetime, comment: "When the baseline was last rebuilt; nil until the first rebuild"
      end
    end

    if table_exists?(:rails_pulse_queries)
      unless column_exists?(:rails_pulse_queries, :baseline_p50_duration)
        add_column :rails_pulse_queries, :baseline_p50_duration, :decimal, precision: 15, scale: 6, comment: "Baseline median duration in milliseconds: traffic-weighted over config.baseline_window of day summaries"
      end
      unless column_exists?(:rails_pulse_queries, :baseline_p90_duration)
        add_column :rails_pulse_queries, :baseline_p90_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 90th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_queries, :baseline_p95_duration)
        add_column :rails_pulse_queries, :baseline_p95_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 95th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_queries, :baseline_sample_count)
        add_column :rails_pulse_queries, :baseline_sample_count, :bigint, null: false, default: 0, comment: "Operations the baseline was built from"
      end
      unless column_exists?(:rails_pulse_queries, :baseline_periods)
        add_column :rails_pulse_queries, :baseline_periods, :integer, null: false, default: 0, comment: "Day summaries the baseline was built from"
      end
      unless column_exists?(:rails_pulse_queries, :baseline_computed_at)
        add_column :rails_pulse_queries, :baseline_computed_at, :datetime, comment: "When the baseline was last rebuilt; nil until the first rebuild"
      end
    end

    if table_exists?(:rails_pulse_jobs)
      unless column_exists?(:rails_pulse_jobs, :baseline_p50_duration)
        add_column :rails_pulse_jobs, :baseline_p50_duration, :decimal, precision: 15, scale: 6, comment: "Baseline median duration in milliseconds: traffic-weighted over config.baseline_window of day summaries"
      end
      unless column_exists?(:rails_pulse_jobs, :baseline_p90_duration)
        add_column :rails_pulse_jobs, :baseline_p90_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 90th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_jobs, :baseline_p95_duration)
        add_column :rails_pulse_jobs, :baseline_p95_duration, :decimal, precision: 15, scale: 6, comment: "Baseline 95th percentile duration in milliseconds"
      end
      unless column_exists?(:rails_pulse_jobs, :baseline_sample_count)
        add_column :rails_pulse_jobs, :baseline_sample_count, :bigint, null: false, default: 0, comment: "Job runs the baseline was built from"
      end
      unless column_exists?(:rails_pulse_jobs, :baseline_periods)
        add_column :rails_pulse_jobs, :baseline_periods, :integer, null: false, default: 0, comment: "Day summaries the baseline was built from"
      end
      unless column_exists?(:rails_pulse_jobs, :baseline_computed_at)
        add_column :rails_pulse_jobs, :baseline_computed_at, :datetime, comment: "When the baseline was last rebuilt; nil until the first rebuild"
      end
    end
  end
end
