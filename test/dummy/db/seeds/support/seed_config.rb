module SeedConfig
  def self.display_db_info
    db_config = ActiveRecord::Base.connection_db_config
    puts "=" * 80
    puts "Adapter: #{db_config.adapter}"
    puts "Database: #{db_config.database}"
    puts "Host: #{db_config.host}" if db_config.host
    puts "=" * 80
    puts ""
  end
end
