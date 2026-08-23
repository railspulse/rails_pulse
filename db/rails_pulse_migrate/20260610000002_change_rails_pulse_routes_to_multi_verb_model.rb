class ChangeRailsPulseRoutesToMultiVerbModel < ActiveRecord::Migration[7.0]
  def up
    # Step 1: Add http_methods JSON array column to routes
    unless column_exists?(:rails_pulse_routes, :http_methods)
      add_column :rails_pulse_routes, :http_methods, :text,
        comment: "JSON array of HTTP methods accepted by this route (e.g., [\"GET\",\"POST\"])"
    end

    # Step 2: Backfill http_methods from the existing single method column
    if column_exists?(:rails_pulse_routes, :method) && column_exists?(:rails_pulse_routes, :http_methods)
      adapter = connection.adapter_name.downcase
      if adapter.include?("mysql")
        execute("UPDATE rails_pulse_routes SET http_methods = CONCAT('[\"', method, '\"]') WHERE http_methods IS NULL AND method IS NOT NULL")
      else
        execute("UPDATE rails_pulse_routes SET http_methods = '[\"' || method || '\"]' WHERE http_methods IS NULL AND method IS NOT NULL")
      end
      execute("UPDATE rails_pulse_routes SET http_methods = '[]' WHERE http_methods IS NULL")

      connection.schema_cache.clear! if connection.respond_to?(:schema_cache)
      http_methods_col = connection.columns(:rails_pulse_routes).find { |c| c.name == "http_methods" }
      change_column_null :rails_pulse_routes, :http_methods, false if http_methods_col&.null
    end

    # Step 3: Add method column to requests so each request records the specific verb used
    unless column_exists?(:rails_pulse_requests, :method)
      add_column :rails_pulse_requests, :method, :string,
        comment: "HTTP method used for this specific request (e.g., GET, POST)"
    end

    # Step 4: Backfill requests.method from routes.method before dropping that column
    if column_exists?(:rails_pulse_routes, :method) && column_exists?(:rails_pulse_requests, :method)
      execute(<<~SQL)
        UPDATE rails_pulse_requests
        SET method = (
          SELECT method FROM rails_pulse_routes
          WHERE rails_pulse_routes.id = rails_pulse_requests.route_id
        )
        WHERE method IS NULL
      SQL
    end

    # Step 5: Merge rows that already share [controller_action, path]. Do not merge
    # null-action rows by path — GET /users (users#index) and POST /users (users#create)
    # must stay distinct until `rails_pulse:migrate_routes` backfills controller_action.
    consolidate_non_null_controller_action_groups

    # Step 6: Swap the unique index from [method, path] to [controller_action, path]
    if index_exists?(:rails_pulse_routes, [ :method, :path ], name: "index_rails_pulse_routes_on_method_and_path")
      remove_index :rails_pulse_routes, name: "index_rails_pulse_routes_on_method_and_path"
    end

    unless index_exists?(:rails_pulse_routes, [ :controller_action, :path ], name: "index_rails_pulse_routes_on_controller_action_and_path")
      add_index :rails_pulse_routes, [ :controller_action, :path ], unique: true,
        name: "index_rails_pulse_routes_on_controller_action_and_path"
    end

    # Step 7: Drop the now-redundant single-method column from routes
    if column_exists?(:rails_pulse_routes, :method)
      remove_column :rails_pulse_routes, :method
    end

    say "Action will stay empty until you run: rails rails_pulse:migrate_routes"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def consolidate_non_null_controller_action_groups
    groups = connection.select_all(<<~SQL).to_a
      SELECT controller_action, path
      FROM rails_pulse_routes
      WHERE controller_action IS NOT NULL
      GROUP BY controller_action, path
      HAVING COUNT(*) > 1
    SQL

    groups.each do |group|
      routes = connection.select_all(
        "SELECT id, http_methods FROM rails_pulse_routes " \
        "WHERE controller_action = #{connection.quote(group["controller_action"])} " \
        "AND path = #{connection.quote(group["path"])} " \
        "ORDER BY id"
      ).to_a
      merge_route_rows!(routes)
    end
  end

  def merge_route_rows!(routes)
    all_methods = routes.flat_map { |r|
      begin
        JSON.parse(r["http_methods"] || "[]")
      rescue JSON::ParserError
        []
      end
    }.uniq.sort

    winner_id = routes.first["id"].to_i
    loser_ids = routes.drop(1).map { |r| r["id"].to_i }
    return if loser_ids.empty?

    loser_list = loser_ids.join(",")

    connection.execute("UPDATE rails_pulse_requests SET route_id = #{winner_id} WHERE route_id IN (#{loser_list})")
    reassign_or_merge_summaries!(winner_id, loser_ids)
    connection.execute("UPDATE rails_pulse_routes SET http_methods = #{connection.quote(all_methods.to_json)} WHERE id = #{winner_id}")
    connection.execute("DELETE FROM rails_pulse_routes WHERE id IN (#{loser_list})")
  end

  # Reassign loser summaries to the winner. When the same period already exists on the
  # winner, combine additive/weighted metrics then delete the loser row (unique index
  # on [summarizable_type, summarizable_id, period_type, period_start]).
  def reassign_or_merge_summaries!(winner_id, loser_ids)
    loser_ids.each do |loser_id|
      source_summaries = connection.select_all(<<~SQL).to_a
        SELECT *
        FROM rails_pulse_summaries
        WHERE summarizable_type = 'RailsPulse::Route'
          AND summarizable_id = #{loser_id.to_i}
      SQL

      source_summaries.each do |source|
        existing = connection.select_one(<<~SQL)
          SELECT *
          FROM rails_pulse_summaries
          WHERE summarizable_type = 'RailsPulse::Route'
            AND summarizable_id = #{winner_id.to_i}
            AND period_type = #{connection.quote(source["period_type"])}
            AND period_start = #{connection.quote(source["period_start"])}
        SQL

        if existing
          merge_summary_row!(existing, source)
          connection.execute("DELETE FROM rails_pulse_summaries WHERE id = #{source["id"].to_i}")
        else
          connection.execute(
            "UPDATE rails_pulse_summaries SET summarizable_id = #{winner_id.to_i} WHERE id = #{source["id"].to_i}"
          )
        end
      end
    end
  end

  def merge_summary_row!(target, source)
    target_count = target["count"].to_i
    source_count = source["count"].to_i
    combined_count = target_count + source_count

    sum_columns = %w[count error_count success_count total_duration status_2xx status_3xx status_4xx status_5xx]
    weighted_columns = %w[avg_duration p50_duration p95_duration p99_duration]

    sets = []

    sum_columns.each do |column|
      next unless target.key?(column)

      sets << "#{column} = #{target[column].to_f + source[column].to_f}"
    end

    if combined_count.positive?
      weighted_columns.each do |column|
        next unless target.key?(column)
        next if target[column].nil? && source[column].nil?

        value = ((target[column].to_f * target_count) + (source[column].to_f * source_count)) / combined_count
        sets << "#{column} = #{value}"
      end
    end

    if target.key?("min_duration")
      mins = [ target["min_duration"], source["min_duration"] ].compact
      sets << "min_duration = #{mins.min}" if mins.any?
    end

    if target.key?("max_duration")
      maxes = [ target["max_duration"], source["max_duration"] ].compact
      sets << "max_duration = #{maxes.max}" if maxes.any?
    end

    sets << "updated_at = #{connection.quote(Time.current)}"
    connection.execute("UPDATE rails_pulse_summaries SET #{sets.join(', ')} WHERE id = #{target["id"].to_i}")
  end
end
