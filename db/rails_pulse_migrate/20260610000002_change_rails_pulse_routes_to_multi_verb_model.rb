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

    # Step 5: Merge routes that share the same [controller_action, path] into one record,
    # combining their http_methods arrays. This collapses e.g. separate GET /sign_in and
    # POST /sign_in records (both sessions#new) into a single route with ["GET","POST"].
    consolidate_route_duplicates

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
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def consolidate_route_duplicates
    groups = connection.select_all(<<~SQL).to_a
      SELECT controller_action, path
      FROM rails_pulse_routes
      WHERE controller_action IS NOT NULL
      GROUP BY controller_action, path
      HAVING COUNT(*) > 1
    SQL

    groups.each do |group|
      ca   = group["controller_action"]
      path = group["path"]

      routes = connection.select_all(
        "SELECT id, http_methods FROM rails_pulse_routes " \
        "WHERE controller_action = #{connection.quote(ca)} AND path = #{connection.quote(path)} " \
        "ORDER BY id"
      ).to_a

      all_methods = routes.flat_map { |r|
        begin; JSON.parse(r["http_methods"] || "[]"); rescue JSON::ParserError; []; end
      }.uniq.sort

      winner_id  = routes.first["id"].to_i
      loser_ids  = routes.drop(1).map { |r| r["id"].to_i }
      next if loser_ids.empty?

      loser_list = loser_ids.join(",")

      connection.execute("UPDATE rails_pulse_requests SET route_id = #{winner_id} WHERE route_id IN (#{loser_list})")
      connection.execute("UPDATE rails_pulse_summaries SET summarizable_id = #{winner_id} WHERE summarizable_id IN (#{loser_list}) AND summarizable_type = 'RailsPulse::Route'")
      connection.execute("UPDATE rails_pulse_routes SET http_methods = #{connection.quote(all_methods.to_json)} WHERE id = #{winner_id}")
      connection.execute("DELETE FROM rails_pulse_routes WHERE id IN (#{loser_list})")
    end
  end
end
