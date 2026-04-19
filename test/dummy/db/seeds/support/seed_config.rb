module SeedConfig
  MODES = {
    quick: { days: 7, requests: 1000, strategy: "minimal" },
    demo: { days: 14, requests: 5000, strategy: "complete" },
    testing: { days: 35, requests: 10000, strategy: "none" },
    custom: {}
  }.freeze

  def self.display_db_info
    db_config = ActiveRecord::Base.connection_db_config
    puts "=" * 80
    puts "Adapter: #{db_config.adapter}"
    puts "Database: #{db_config.database}"
    puts "Host: #{db_config.host}" if db_config.host
    puts "=" * 80
    puts ""
  end

  def self.mode
    @mode ||= begin
      mode_name = ENV["SEED_MODE"]&.to_sym || :quick
      unless MODES.key?(mode_name)
        puts "⚠️  Unknown SEED_MODE '#{mode_name}', falling back to 'quick'"
        mode_name = :quick
      end
      mode_name
    end
  end

  def self.mode_defaults
    MODES[mode]
  end

  def self.days_ago
    ENV["HISTORICAL_DAYS"]&.to_i || mode_defaults[:days] || 7
  end

  def self.request_count
    ENV["HISTORICAL_REQUEST_COUNT"]&.to_i || mode_defaults[:requests] || 1000
  end

  def self.summary_strategy
    # AUTO_BACKFILL_SUMMARIES takes precedence (legacy support)
    if ENV.key?("AUTO_BACKFILL_SUMMARIES")
      return ENV["AUTO_BACKFILL_SUMMARIES"] == "true" ? "complete" : "none"
    end

    ENV["SUMMARY_STRATEGY"] || mode_defaults[:strategy] || "minimal"
  end

  def self.display_config
    puts "\n" + "=" * 80
    puts "SEED CONFIGURATION"
    puts "=" * 80
    puts "Mode: #{mode}"
    puts "Historical days: #{days_ago}"
    puts "Request count: #{request_count}"
    puts "Summary strategy: #{summary_strategy}"
    puts "=" * 80
    puts ""
  end

  def self.validate_config
    if days_ago > 14 && summary_strategy == "minimal"
      puts "\n⚠️  WARNING: Generating #{days_ago} days of data with 'minimal' summary strategy"
      puts "   This will trigger storage pressure warnings (retention period is typically 14 days)"
      puts "   Consider using SUMMARY_STRATEGY=smart or SUMMARY_STRATEGY=complete"
      puts ""
    end
  end
end
