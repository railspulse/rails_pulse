module RailsPulse
  class Job < RailsPulse::ApplicationRecord
    include Taggable

    self.table_name = "rails_pulse_jobs"

    has_many :runs,
             class_name: "RailsPulse::JobRun",
             foreign_key: :job_id,
             inverse_of: :job,
             dependent: :destroy

    validates :name, presence: true, uniqueness: true

    def self.ransackable_attributes(auth_object = nil)
      %w[id name queue_name runs_count failures_count retries_count avg_duration]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[runs]
    end

    scope :by_queue, ->(queue) { where(queue_name: queue) }
    scope :with_failures, -> { where("failures_count > 0") }
    scope :ordered_by_runs, -> { order(runs_count: :desc) }

    def apply_run!(run)
      return unless run.duration

      duration = run.duration.to_f

      with_lock do
        reload
        total_runs = runs_count.to_i
        previous_total = [ total_runs - 1, 0 ].max
        previous_average = avg_duration.to_f

        new_average = if previous_total.zero?
          duration
        else
          ((previous_average * previous_total) + duration) / (previous_total + 1)
        end

        updates = { avg_duration: new_average }
        if run.failure_like_status?
          updates[:failures_count] = failures_count + 1
        end
        if run.status == "retried"
          updates[:retries_count] = retries_count + 1
        end

        update!(updates)
      end
    end

    def failure_rate
      return 0.0 if runs_count.zero?

      ((failures_count.to_f / runs_count) * 100).round(2)
    end

    def performance_status
      thresholds = RailsPulse.configuration.job_thresholds
      duration = avg_duration.to_f

      if duration < thresholds[:slow]
        :fast
      elsif duration < thresholds[:very_slow]
        :slow
      elsif duration < thresholds[:critical]
        :very_slow
      else
        :critical
      end
    end

    def to_param
      id.to_s
    end

    def to_breadcrumb
      name
    end
  end
end
