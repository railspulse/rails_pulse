class AddQueryAnalysisColumns < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    unless column_exists?(:rails_pulse_queries, :analyzed_at)
      add_column :rails_pulse_queries, :analyzed_at, :datetime, comment: "When query analysis was last performed"
    end

    unless column_exists?(:rails_pulse_queries, :explain_plan)
      add_column :rails_pulse_queries, :explain_plan, :text, comment: "EXPLAIN output from actual SQL execution"
    end

    unless column_exists?(:rails_pulse_queries, :issues)
      add_column :rails_pulse_queries, :issues, :text, comment: "JSON array of detected performance issues"
    end

    unless column_exists?(:rails_pulse_queries, :metadata)
      add_column :rails_pulse_queries, :metadata, :text, comment: "JSON object containing query complexity metrics"
    end

    unless column_exists?(:rails_pulse_queries, :query_stats)
      add_column :rails_pulse_queries, :query_stats, :text, comment: "JSON object with query characteristics analysis"
    end

    unless column_exists?(:rails_pulse_queries, :backtrace_analysis)
      add_column :rails_pulse_queries, :backtrace_analysis, :text, comment: "JSON object with call chain and N+1 detection"
    end

    unless column_exists?(:rails_pulse_queries, :index_recommendations)
      add_column :rails_pulse_queries, :index_recommendations, :text, comment: "JSON array of database index recommendations"
    end

    unless column_exists?(:rails_pulse_queries, :n_plus_one_analysis)
      add_column :rails_pulse_queries, :n_plus_one_analysis, :text, comment: "JSON object with enhanced N+1 query detection results"
    end

    unless column_exists?(:rails_pulse_queries, :suggestions)
      add_column :rails_pulse_queries, :suggestions, :text, comment: "JSON array of optimization recommendations"
    end
  end
end
