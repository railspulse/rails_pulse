module Statistics
  def self.display!
    puts "\n" + ("=" * 80)
    puts "SEED STATISTICS"
    puts "=" * 80

    display_base_stats
    display_rails_pulse_stats if SeedConfig.days_ago > 0

    puts "=" * 80
  end

  private

  def self.display_base_stats
    puts "\nBase Application:"
    puts "  Users: #{User.count}"
    puts "  Posts: #{Post.count} (#{Post.where(published: true).count} published)"
    puts "  Comments: #{Comment.count}"
  end

  def self.display_rails_pulse_stats
    puts "\nRails Pulse Performance Data:"
    puts "  Routes: #{RailsPulse::Route.count}"
    puts "  Queries: #{RailsPulse::Query.count}"
    puts "  Requests: #{RailsPulse::Request.count}"
    puts "  Operations: #{RailsPulse::Operation.count}"
    puts "  Jobs: #{RailsPulse::Job.count}"
    puts "  Job Runs: #{RailsPulse::JobRun.count}"
    puts "  Summaries: #{RailsPulse::Summary.count}"

    if RailsPulse::Request.any?
      avg_request_duration = RailsPulse::Request.average(:duration).to_f.round(2)
      error_rate = (RailsPulse::Request.where(is_error: true).count.to_f / RailsPulse::Request.count * 100).round(2)
      puts "\n  Avg Request Duration: #{avg_request_duration}ms"
      puts "  Request Error Rate: #{error_rate}%"
    end

    if RailsPulse::JobRun.any?
      avg_job_duration = RailsPulse::JobRun.average(:duration).to_f.round(2)
      failure_rate = (RailsPulse::JobRun.where(status: %w[failed discarded]).count.to_f / RailsPulse::JobRun.count * 100).round(2)
      puts "  Avg Job Duration: #{avg_job_duration}ms"
      puts "  Job Failure Rate: #{failure_rate}%"
    end

    analyzed_count = RailsPulse::Query.where.not(analyzed_at: nil).count
    puts "\n  Analyzed Queries: #{analyzed_count}"
    puts "  Queries with Issues: #{RailsPulse::Query.where.not(issues: [ nil, "[]" ]).count}"
  end
end
