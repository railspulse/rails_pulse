module ControllerTestHelpers
  # Authentication stubbing patterns
  def stub_authentication(user: nil, authenticated: true)
    if authenticated
      user ||= create(:user) if defined?(:user)
      session[:user_id] = user&.id
    else
      session.clear
    end
  end

  def stub_admin_authentication
    stub_authentication(authenticated: true)
    session[:admin] = true
  end

  # Rails Pulse engine route helpers
  def rails_pulse_path(path)
    "/rails_pulse#{path}"
  end

  def get_rails_pulse(action, **params)
    get rails_pulse_path("/#{action}"), params: params
  end

  def post_rails_pulse(action, **params)
    post rails_pulse_path("/#{action}"), params: params
  end

  # Response assertion patterns
  def assert_successful_response(expected_status: 200)
    assert_response expected_status
    assert_not_nil response.body
  end

  def assert_json_response(expected_keys: [])
    assert_response :success
    assert_equal "application/json", response.content_type.split(";").first

    if expected_keys.any?
      json = JSON.parse(response.body)

      expected_keys.each do |key|
        assert json.key?(key.to_s), "Expected JSON response to include key '#{key}'"
      end
    end
  end

  def assert_html_response
    assert_response :success
    assert_equal "text/html", response.content_type.split(";").first
  end

  def assert_redirected_with_flash(expected_path: nil, flash_type: :notice)
    assert_response :redirect
    assert_not_nil flash[flash_type], "Expected flash[#{flash_type}] to be set"
    assert_redirected_to expected_path if expected_path
  end

  # Chart data stubbing helpers
  def stub_chart_data(data: [], labels: [])
    chart_data = {
      data: data,
      labels: labels
    }
    assigns(:chart_data).stubs(:to_h).returns(chart_data) if assigns(:chart_data)
    chart_data
  end

  def stub_performance_data(
    fast_count: 10,
    slow_count: 5,
    critical_count: 1,
    timeframe: 1.day.ago..Time.current
  )
    {
      fast: fast_count,
      slow: slow_count,
      critical: critical_count,
      timeframe: timeframe
    }
  end

  # Error handling assertions
  def assert_handles_missing_record
    assert_response :not_found
  end

  def assert_handles_invalid_params
    assert_response :unprocessable_entity
  end

  # Pagination helpers
  def assert_paginated_response(expected_total: nil)
    assert_successful_response
    if expected_total
      assigns_pagy = assigns(:pagy)

      assert_not_nil assigns_pagy, "Expected @pagy to be assigned"
      assert_equal expected_total, assigns_pagy.count if assigns_pagy.respond_to?(:count)
    end
  end
end
