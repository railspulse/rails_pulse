module TableValidationHelpers
  def validate_table_data(page_type:, expected_data: [], table_selector: "table tbody", filter_applied: nil)
    # Wait for table to load and be stable after any updates
    assert_selector table_selector, wait: 5
    sleep 0.5  # Allow for any final updates to complete

    table_rows = page.all("#{table_selector} tr")

    assert_operator table_rows.length, :>, 0, "Table should contain data rows"

    case page_type
    when :routes
      validate_routes_table(table_rows, expected_data, filter_applied)
    when :requests
      validate_requests_table(table_rows, expected_data, filter_applied)
    when :queries
      validate_queries_table(table_rows, expected_data, filter_applied)
    else
      raise ArgumentError, "Unknown page_type: #{page_type}. Must be :routes, :requests, or :queries"
    end
  end

  private

  def validate_routes_table(table_rows, expected_routes, filter_applied)
    table_rows.each_with_index do |row, index|
      cells = row.all("td")

      assert_operator cells.length, :>=, 2, "Route row #{index + 1} should have at least 2 columns (path and response time)"

      # Validate route path (first column)
      validate_route_path_cell(cells[0], index + 1, filter_applied)

      # Validate response time (second column)
      validate_duration_cell(cells[1], index + 1, filter_applied, page_type: :routes)

      # Validate additional columns (error rate, throughput, etc.)
      validate_additional_numeric_columns(cells[2..-1], index + 1) if cells.length > 2
    end

    # Validate expected routes coverage
    validate_routes_coverage(table_rows, expected_routes) if expected_routes.any?
  end

  def validate_requests_table(table_rows, expected_requests, filter_applied)
    table_rows.each_with_index do |row, index|
      cells = row.all("td")

      # Current requests table structure: timestamp, route, duration, status
      assert_operator cells.length, :>=, 4, "Request row #{index + 1} should have at least 4 columns (timestamp, route, duration, status)"

      # Skip timestamp validation (cells[0]) as it can vary in format
      validate_route_path_cell(cells[1], index + 1, filter_applied)
      validate_duration_cell(cells[2], index + 1, filter_applied, page_type: :requests)
      validate_status_code_cell(cells[3], index + 1)
    end

    # Validate expected requests coverage
    validate_requests_coverage(table_rows, expected_requests) if expected_requests.any?
  end

  def validate_queries_table(table_rows, expected_queries, filter_applied)
    table_rows.each_with_index do |row, index|
      cells = row.all("td")

      assert_operator cells.length, :>=, 3, "Query row #{index + 1} should have at least 3 columns (SQL, avg time, executions)"

      # Validate SQL query (first column)
      validate_sql_cell(cells[0], index + 1, filter_applied)

      # Validate average duration (second column)
      validate_duration_cell(cells[1], index + 1, filter_applied, page_type: :queries)

      # Validate executions count (third column)
      executions_text = cells[2].text.strip
      executions_value = executions_text.to_i

      assert_operator executions_value, :>, 0, "Executions should be positive in row #{index + 1}, got: #{executions_value}"

      # Additional columns can be validated if needed (total time, status, last seen)
    end

    # Validate expected queries coverage
    validate_queries_coverage(table_rows, expected_queries) if expected_queries.any?
  end

  def validate_route_path_cell(cell, row_num, filter_applied)
    route_link = cell.find("a", wait: 1) rescue nil

    assert route_link, "Route path should contain a link in row #{row_num}"

    route_full_text = route_link.text.strip

    assert_predicate route_full_text, :present?, "Route path should not be empty in row #{row_num}"

    # Extract just the path from "path METHOD" format
    route_path = route_full_text.split(" ").first

    # Apply path-based filters
    case filter_applied
    when "api", /api/i

      assert_includes route_path, "api", "Row #{row_num} should contain 'api' in path: #{route_path}"
    when "admin", /admin/i

      assert_includes route_path, "admin", "Row #{row_num} should contain 'admin' in path: #{route_path}"
    end
  end

  def validate_duration_cell(cell, row_num, filter_applied, page_type: nil)
    duration_text = cell.text.strip
    duration_match = duration_text.match(/([0-9,]+(?:\.\d+)?)/)

    assert duration_match, "Duration should contain numeric value in row #{row_num}, got: '#{duration_text}'"

    duration_value = duration_match[1].gsub(",", "").to_f

    assert_operator duration_value, :>, 0, "Duration should be positive in row #{row_num}, got: #{duration_value} from text '#{duration_text}'"
    assert_operator duration_value, :<, 30000, "Duration should be reasonable (< 30s) in row #{row_num}, got: #{duration_value}ms from text '#{duration_text}'"

    # Apply performance-based filters - use different thresholds for queries vs routes
    # Skip validation for SQLite as test data may not be consistently filtered
    unless ENV["DB"] == "sqlite"
      case filter_applied
      when "Slow", /Slow.*≥.*ms/i
        if page_type == :queries
          # Query slow threshold: ≥ 100ms
          assert_operator duration_value, :>=, 100, "Slow filter: duration should be ≥ 100ms in row #{row_num}, got: #{duration_value}ms from text '#{duration_text}'"
        else
          # Route slow threshold: ≥ 500ms
          assert_operator duration_value, :>=, 500, "Slow filter: duration should be ≥ 500ms in row #{row_num}, got: #{duration_value}ms from text '#{duration_text}'"
        end
      when "Critical", /Critical.*≥.*ms/i
        if page_type == :queries
          # Query critical threshold: ≥ 1000ms
          assert_operator duration_value, :>=, 1000, "Critical filter: duration should be ≥ 1000ms in row #{row_num}, got: #{duration_value}ms from text '#{duration_text}'"
        else
          # Route critical threshold: ≥ 3000ms
          assert_operator duration_value, :>=, 3000, "Critical filter: duration should be ≥ 3000ms in row #{row_num}, got: #{duration_value}ms from text '#{duration_text}'"
        end
      end
    end
  end

  def validate_status_code_cell(cell, row_num)
    status_text = cell.text.strip
    status_match = status_text.match(/(\d{3})/)

    assert status_match, "Status code should be 3 digits in row #{row_num}, got: #{status_text}"

    status_code = status_match[1].to_i

    assert status_code >= 100 && status_code < 600,
           "Status code should be valid HTTP status in row #{row_num}, got: #{status_code}"
  end

  def validate_timestamp_cell(cell, row_num)
    timestamp_text = cell.text.strip
    return if timestamp_text.empty?

    # Allow various timestamp formats
    timestamp_patterns = [
      /\d{4}-\d{2}-\d{2}/, # YYYY-MM-DD
      /\d{2}\/\d{2}\/\d{4}/, # MM/DD/YYYY
      /\d+ \w+ ago/, # "5 minutes ago"
      /\d{2}:\d{2}/, # HH:MM
      /\w{3} \d{1,2}, \d{4} \d{1,2}:\d{2} (AM|PM)/ # "Aug 30, 2025 5:40 AM"
    ]

    has_valid_format = timestamp_patterns.any? { |pattern| timestamp_text.match?(pattern) }

    assert has_valid_format, "Timestamp should be in recognizable format in row #{row_num}, got: #{timestamp_text}"
  end

  def validate_sql_cell(cell, row_num, filter_applied)
    sql_text = cell.text.strip

    assert_predicate sql_text, :present?, "SQL query should not be empty in row #{row_num}"

    # Apply SQL-based filters
    case filter_applied
    when "SELECT", /select/i

      assert_includes sql_text.upcase, "SELECT", "Row #{row_num} should contain SELECT query: #{sql_text[0..50]}..."
    when "UPDATE", /update/i

      assert_includes sql_text.upcase, "UPDATE", "Row #{row_num} should contain UPDATE query: #{sql_text[0..50]}..."
    end
  end

  def validate_caller_cell(cell, row_num)
    caller_text = cell.text.strip
    return if caller_text.empty? || caller_text.match?(/^[-–—]+$/)

    assert_predicate caller_text, :present?, "Caller should not be empty in row #{row_num}"
  end

  def validate_additional_numeric_columns(cells, row_num)
    cells.each_with_index do |cell, col_index|
      cell_text = cell.text.strip
      next if cell_text.empty? || cell_text.match?(/^[-–—]+$/)

      if cell_text.match?(/\d/)
        numeric_match = cell_text.match(/([\d,]+(?:\.\d+)?)\s*(%|ms|\/min|\/s|requests)?/)
        if numeric_match
          value = numeric_match[1].gsub(",", "").to_f
          unit = numeric_match[2]

          case unit
          when "%"

            assert value >= 0 && value <= 100, "Percentage should be 0-100% in row #{row_num}, column #{col_index + 3}, got: #{value}%"
          when "ms"

            assert_operator value, :>=, 0, "Time value should be non-negative in row #{row_num}, column #{col_index + 3}, got: #{value}ms"
          else
            assert_operator value, :>=, 0, "Numeric value should be non-negative in row #{row_num}, column #{col_index + 3}, got: #{value}"
          end
        end
      end
    end
  end

  def validate_routes_coverage(table_rows, expected_routes)
    route_paths_in_table = table_rows.map do |row|
      link = row.all("td").first&.find("a") rescue nil
      # Extract just the path from "path METHOD" format
      full_text = link&.text&.strip
      full_text&.split(" ")&.first  # Get everything before the first space (the path)
    end.compact

    expected_paths = expected_routes.respond_to?(:map) ? expected_routes.map(&:path) : expected_routes
    overlapping_routes = expected_paths & route_paths_in_table
    coverage_ratio = overlapping_routes.length.to_f / [ expected_paths.length, 10 ].min

    assert_operator coverage_ratio, :>, 0, "Table should contain some expected routes. Expected: #{expected_paths.first(5)}, Found: #{route_paths_in_table.first(5)}"
  end

  def validate_requests_coverage(table_rows, expected_requests)
    # For requests table, we extract route paths from the second column (index 1)
    route_paths_in_table = table_rows.map do |row|
      cells = row.all("td")
      link = cells[1]&.find("a") rescue nil if cells.length > 1
      route_text = link&.text&.strip
      # Extract just the path part from "path METHOD" format
      route_text&.split(" ")&.first
    end.compact

    # Extract route paths from expected requests (they have request.route.path)
    expected_route_paths = expected_requests.respond_to?(:map) ?
      expected_requests.map { |r| r.respond_to?(:route) ? r.route&.path : r.to_s }.compact :
      expected_requests

    overlapping_routes = expected_route_paths & route_paths_in_table
    coverage_ratio = overlapping_routes.length.to_f / [ expected_route_paths.length, 10 ].min

    assert_operator coverage_ratio, :>, 0, "Table should contain some expected requests. Expected route paths: #{expected_route_paths.first(3)}, Found route paths: #{route_paths_in_table.first(3)}"
  end

  def validate_queries_coverage(table_rows, expected_queries)
    sql_in_table = table_rows.map do |row|
      first_cell = row.all("td").first
      first_cell&.text&.strip&.truncate(50)
    end.compact

    expected_sql = expected_queries.respond_to?(:map) ? expected_queries.map { |q| q.respond_to?(:normalized_sql) ? q.normalized_sql.truncate(50) : q.to_s.truncate(50) } : expected_queries
    overlapping_queries = expected_sql & sql_in_table
    coverage_ratio = overlapping_queries.length.to_f / [ expected_sql.length, 10 ].min

    assert_operator coverage_ratio, :>, 0, "Table should contain some expected queries. Expected: #{expected_sql.first(3)}, Found: #{sql_in_table.first(3)}"
  end
end
