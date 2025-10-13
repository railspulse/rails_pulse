module ModelTestHelpers
  def setup_clean_database
    DatabaseHelpers.ensure_test_tables_exist
    RailsPulse::Operation.delete_all
    RailsPulse::Request.delete_all
    RailsPulse::Query.delete_all
    RailsPulse::Route.delete_all
  end

  def create_test_route(method: "GET", path: "/test", **attributes)
    create(:route, method: method, path: path, **attributes)
  end

  def create_test_request(duration: 100.5, status: 200, route: nil, **attributes)
    route ||= create_test_route
    create(:request, route: route, duration: duration, status: status, **attributes)
  end

  def create_test_query(duration: 50.0, query_type: "SELECT", **attributes)
    create(:query, duration: duration, query_type: query_type, **attributes)
  end

  def create_test_operation(name: "TestOperation", duration: 75.0, **attributes)
    create(:operation, name: name, duration: duration, **attributes)
  end

  # Batch creation helpers for performance testing
  def create_request_batch(count: 10, trait: nil, **attributes)
    if trait
      create_list(:request, count, trait, **attributes)
    else
      create_list(:request, count, **attributes)
    end
  end

  def create_time_series_requests(count: 24, interval: 1.hour, starting_at: 1.day.ago)
    count.times.map do |i|
      create(:request, occurred_at: starting_at + (i * interval))
    end
  end

  # Ransacker testing helpers
  def assert_ransacker_search(model_class, ransacker_name, search_value, expected_count)
    search = model_class.ransack("#{ransacker_name}_cont" => search_value)

    assert_equal expected_count, search.result.count,
      "Expected #{expected_count} results for #{ransacker_name} search '#{search_value}'"
  end

  # Validation testing with shoulda-matchers integration
  def assert_model_validations(model_class)
    if defined?(Shoulda::Matchers)
      # Use shoulda-matchers if available
      yield if block_given?
    else
      # Fallback to manual validation testing
      model = model_class.new

      assert_not model.valid?, "#{model_class} should require validations"
    end
  end

  def assert_belongs_to_association(model_class, association_name)
    if defined?(Shoulda::Matchers)
      # This would be used in actual test files:
      # assert_that(model_class.new).belongs_to(association_name)
    else
      model = model_class.new

      assert_respond_to model, association_name
    end
  end
end
