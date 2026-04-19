class JobsController < ApplicationController
  ADAPTERS = [
    { key: "sidekiq",      label: "Sidekiq",      tracking: "enhanced",  gem: "sidekiq",                  description: "Custom middleware · Captures jid, retry count, enqueued_at" },
    { key: "delayed_job",  label: "Delayed Job",  tracking: "enhanced",  gem: "delayed_job_active_record", description: "Custom plugin · Captures attempt count, handler class, created_at" },
    { key: "good_job",     label: "Good Job",     tracking: "universal", gem: "good_job",                 description: "ActiveJob around_perform · Standard job metadata" },
    { key: "solid_queue",  label: "Solid Queue",  tracking: "universal", gem: "solid_queue",              description: "ActiveJob around_perform · Standard job metadata" },
    { key: "resque",       label: "Resque",       tracking: "universal", gem: "resque",                   description: "ActiveJob around_perform · Standard job metadata" }
  ].freeze

  def index
    @adapters = ADAPTERS.map do |a|
      a.merge(installed: Gem.loaded_specs.key?(a[:gem]))
    end
    @recent_runs = RailsPulse::JobRun.order(occurred_at: :desc).limit(10).includes(:job)
    @last_result = session.delete("job_result")
  end

  def trigger
    adapter  = params[:adapter]
    job_type = params[:job_type]

    unless ADAPTERS.map { |a| a[:key] }.include?(adapter)
      redirect_to jobs_path, alert: "Unknown adapter"
      return
    end

    result = run_demo_job(adapter, job_type)
    session["job_result"] = result
    redirect_to jobs_path
  end

  private

  def run_demo_job(adapter, job_type)
    job_id = SecureRandom.uuid
    class_name = "Demo#{adapter.split('_').map(&:capitalize).join}Job"

    job_wrapper = RailsPulse::Adapters::JobWrapper.new(
      job_id:      job_id,
      class_name:  class_name,
      queue_name:  queue_for(adapter),
      arguments:   [ job_type ],
      enqueued_at: rand(5..60).seconds.ago,
      executions:  0
    )

    result = { "adapter" => adapter, "job_type" => job_type, "class_name" => class_name,
               "status" => nil, "duration" => nil, "error" => nil, "run_id" => nil,
               "adapter_recorded" => nil }

    begin
      RailsPulse::JobRunCollector.track(job_wrapper, adapter: adapter) do
        execute_job_work(job_type)
      end
      result["status"] = "success"
    rescue StandardError => e
      result["status"] = "failed"
      result["error"]  = e.message
    end

    run = RailsPulse::JobRun.find_by(run_id: job_id)
    result["run_id"]           = run&.run_id&.first(8)
    result["duration"]         = run&.duration&.round(1)
    result["adapter_recorded"] = run&.adapter
    result
  end

  def execute_job_work(job_type)
    case job_type
    when "fast"
      User.count
      Post.count
    when "slow"
      sleep(rand(1.0..2.5))
      User.joins(:posts).group("users.id").count
    when "failing"
      User.count
      raise StandardError, "Demo failure at #{Time.current.strftime('%H:%M:%S')}"
    end
  end

  def queue_for(adapter)
    { "sidekiq" => "critical", "delayed_job" => "mailers" }.fetch(adapter, "default")
  end
end
