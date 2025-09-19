class AddAnalysisToRailsPulseQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :rails_pulse_queries, :analyzed_at, :datetime, comment: "When query analysis was last performed"
    add_column :rails_pulse_queries, :explain_plan, :text, comment: "EXPLAIN output from actual SQL execution"
    add_column :rails_pulse_queries, :issues, :text, comment: "JSON array of detected performance issues"
    add_column :rails_pulse_queries, :metadata, :text, comment: "JSON object containing query complexity metrics"
    add_column :rails_pulse_queries, :query_stats, :text, comment: "JSON object with query characteristics analysis"
    add_column :rails_pulse_queries, :backtrace_analysis, :text, comment: "JSON object with call chain and N+1 detection"
    add_column :rails_pulse_queries, :suggestions, :text, comment: "JSON array of optimization recommendations"
    add_column :rails_pulse_queries, :index_recommendations, :text, comment: "JSON array of database index recommendations"
    add_column :rails_pulse_queries, :n_plus_one_analysis, :text, comment: "JSON object with enhanced N+1 query detection results"
  end
end
