# Testing Best Practices for RailsPulse

This document outlines the testing standards and best practices for the RailsPulse project. Follow these guidelines to ensure consistent, maintainable, and reliable tests.

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [Additional Best Practices](#additional-best-practices)
3. [Test Organization](#test-organization)
4. [Assertion Guidelines](#assertion-guidelines)
5. [Time-Based Testing](#time-based-testing)
6. [Data Management](#data-management)
7. [Edge Cases and Validation](#edge-cases-and-validation)
8. [Examples](#examples)

---

## Core Principles

### 1. Execute real code - minimize mocking and stubbing

Tests should execute the actual application code to provide meaningful coverage and catch real bugs. Over-mocking creates false confidence: tests pass but code is never actually run.

**❌ Bad - Mocking prevents real execution:**
```ruby
test "calculates total with tax" do
  # Stubbing prevents calculate_tax from actually running
  stub(:calculate_tax, 10.0) do
    result = order.total_with_tax
    assert_equal 110.0, result
  end
  # Code coverage: 0% for calculate_tax method
end
```

**✅ Good - Real execution:**
```ruby
test "calculates total with tax" do
  order = create_order(subtotal: 100.0, tax_rate: 0.10)

  result = order.total_with_tax

  assert_equal 110.0, result
  # Code coverage: 100% - calculate_tax actually executed
end
```

**When to use mocking/stubbing:**
- External API calls (network requests, third-party services)
- Time-consuming operations (file I/O, complex calculations) where fixtures are impractical
- Dependencies that are difficult to set up in test environment

**When NOT to use mocking/stubbing:**
- Your own application code (models, services, helpers, concerns)
- Rails framework methods (they're already tested by Rails)
- Simple calculations or data transformations

---

### 2. DO NOT test the existence of private methods

Private methods are implementation details. Only test the public API.

**❌ Bad:**
```ruby
test "controller has required private methods" do
  controller = RailsPulse::JobsController.new
  private_methods = controller.private_methods

  assert_includes private_methods, :set_job  # DON'T DO THIS
end
```

**✅ Good:**
```ruby
test "index action loads successfully" do
  get rails_pulse.jobs_path

  assert_response :success
  assert_not_nil assigns(:jobs)
end
```

---

### 2. In general, only test public methods

Focus on the class's public interface. Test behavior, not implementation. Private methods are tested indirectly through public methods.

---

### 3. Primarily use fixtures for data

Use existing fixtures when possible. Only create records with ActiveRecord when you need one-off data that doesn't fit fixtures.

**✅ Good:**
```ruby
test "calculates average for job" do
  @job = rails_pulse_jobs(:report_job)

  result = calculate_average(@job)

  assert_equal 100.0, result
end
```

**❌ Bad:**
```ruby
test "calculates average for job" do
  @job = RailsPulse::Job.create!(
    name: "TestJob",
    queue_name: "default",
    runs_count: 0,
    failures_count: 0
  )

  result = calculate_average(@job)

  assert_equal 100.0, result
end
```

**When to create records:**
- Testing with specific edge-case values not in fixtures
- Creating multiple similar records with slight variations
- One-off test scenarios

---

### 4. Do NOT use `rescue` in tests

Every method should run as expected without error handling. Use `assert_raises` to test exception cases explicitly.

**❌ Bad:**
```ruby
test "calculates average correctly" do
  begin
    @job = Job.create!(name: "Test")
    result = SomeService.calculate(@job)
    assert_equal 100, result.average
  rescue => e
    assert true  # DON'T DO THIS
  end
end
```

**✅ Good:**
```ruby
test "calculates average correctly" do
  @job = rails_pulse_jobs(:report_job)
  create_summary(job: @job, count: 10, avg: 100)

  result = SomeService.calculate(@job)

  assert_equal 100, result.average
end

test "raises error for invalid job" do
  assert_raises(ArgumentError) do
    SomeService.calculate(nil)
  end
end
```

---

### 5. Do NOT return a passing expectation when something unexpected happens

Don't use catch-all success assertions. Every assertion should be specific and meaningful.

**❌ Bad:**
```ruby
test "processes job" do
  begin
    process_job(@job)
    assert true  # DON'T DO THIS
  rescue
    assert false
  end
end
```

**✅ Good:**
```ruby
test "processes job successfully" do
  @job = rails_pulse_jobs(:report_job)

  result = process_job(@job)

  assert_equal "success", result.status
  assert_equal 1, @job.reload.runs_count
end
```

---

## Additional Best Practices

### 6. Organize tests with comment headers

Group related tests with clear section comments for better readability:

```ruby
# Structure Tests

test "card returns hash with required keys" do
  # ...
end

# Calculation Tests

test "card calculates average correctly" do
  # ...
end

# Edge Cases

test "card handles empty data" do
  # ...
end
```

---

### 7. Use descriptive test names

Follow the pattern: **Subject + Action + Context**

**✅ Good:**
- `"card calculates average duration for specific job"`
- `"index action loads successfully with pagination"`
- `"breadcrumbs converts numeric segments to resource names using to_breadcrumb for Route"`

**❌ Bad:**
- `"test 1"`
- `"it works"`
- `"average calculation"`

---

### 8. Use assert_operator for comparisons

**✅ Good:**
```ruby
assert_operator jobs.size, :<=, 10
assert_operator current.runs_count, :>=, next_job.runs_count
assert_operator RailsPulse::JobsController, :<, RailsPulse::ApplicationController
```

**❌ Bad:**
```ruby
assert jobs.size <= 10
assert current.runs_count >= next_job.runs_count
```

---

### 9. Use assert_includes for collection membership

**✅ Good:**
```ruby
assert_includes job.errors[:name], "can't be blank"
assert_includes result.keys, :summary
assert_includes RailsPulse::JobsController.included_modules, TagFilterConcern
```

**❌ Bad:**
```ruby
assert result.keys.include?(:summary)
assert job.errors[:name].include?("can't be blank")
```

---

### 10. Use assert_in_delta for floating point comparisons

**✅ Good:**
```ruby
assert_in_delta 50.0, job.failure_rate
assert_in_delta 200.0, job.avg_duration, 0.01
```

**❌ Bad:**
```ruby
assert_equal 50.0, job.failure_rate  # Can fail due to floating point precision
```

---

### 11. Test edge cases comprehensively

Always test:
- Empty/nil values
- Zero counts
- Missing data
- Boundary conditions

```ruby
# Edge Cases

test "handles job with no runs" do
  card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
  result = card.to_metric_card

  assert_equal "0 runs", result[:summary]
end

test "handles only current window data" do
  create_job_summary(job: @job, days_ago: 3, count: 15)

  card = RailsPulse::Jobs::Cards::TotalRuns.new(job: @job)
  result = card.to_metric_card

  assert_equal "15 runs", result[:summary]
end

test "handles 100% failure rate" do
  create_job_summary(job: @job, days_ago: 3, count: 10, error_count: 10)

  card = RailsPulse::Jobs::Cards::FailureRate.new(job: @job)
  result = card.to_metric_card

  assert_equal "100.0%", result[:summary]
end
```

---

### 12. Use travel_to for time-based testing

Always clean up with `travel_back` in teardown.

```ruby
def setup
  ENV["TEST_TYPE"] = "functional"
  super

  @now = Time.current
  travel_to @now
end

def teardown
  travel_back
  super
end
```

---

### 13. Create helper methods for repetitive test data setup

Use named parameters for clarity and flexibility.

```ruby
private

def create_job_summary(job:, days_ago:, count:, avg_duration:)
  period_start = days_ago.days.ago.beginning_of_day

  RailsPulse::Summary.create!(
    summarizable_type: "RailsPulse::Job",
    summarizable_id: job.id,
    period_start: period_start,
    period_end: period_start.end_of_day,
    period_type: "day",
    count: count,
    avg_duration: avg_duration
  )
end
```

---

### 14. Use ensure blocks to restore configuration changes

Always restore original configuration values to avoid test pollution.

```ruby
test "respects custom thresholds" do
  original_thresholds = RailsPulse.configuration.job_thresholds.dup

  RailsPulse.configuration.job_thresholds = { slow: 100 }

  # test code here
  assert_equal "slow", job.performance_status

ensure
  RailsPulse.configuration.job_thresholds = original_thresholds
end
```

---

### 15. Document complex calculations with inline comments

Make tests self-documenting by showing the math inline.

```ruby
# Current window data (3 days ago: 100ms avg, 10 runs)
create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)

# Previous window data (10 days ago: 200ms avg, 5 runs)
create_job_summary(job: @job, days_ago: 10, count: 5, avg_duration: 200.0)

# Total average: (100*10 + 200*5) / (10+5) = 2000/15 = 133.3ms
assert_equal "133 ms", result[:summary]

# Trend: current 100ms vs previous 200ms = -50% (improvement)
assert_equal "trending-down", result[:trend_icon]
assert_equal "50.0%", result[:trend_amount]
```

---

### 16. Use each_cons for testing ordered collections

Guard against single-item collections to avoid errors.

```ruby
test "index action orders jobs by runs_count desc" do
  get rails_pulse.jobs_path

  assert_response :success
  jobs = assigns(:jobs)

  # Verify jobs are ordered by runs_count desc
  if jobs.size > 1
    jobs.each_cons(2) do |current, next_job|
      assert_operator current.runs_count, :>=, next_job.runs_count
    end
  end
end
```

---

### 17. Test both positive and negative cases

Always test validation failures, not just successes.

```ruby
# Positive case
test "creates valid job" do
  job = Job.create!(name: "ValidJob", queue_name: "default")

  assert job.persisted?
  assert_equal "ValidJob", job.name
end

# Negative cases
test "validates presence of name" do
  job = Job.new

  assert_not job.valid?
  assert_includes job.errors[:name], "can't be blank"
end

test "validates uniqueness of name" do
  existing_job = rails_pulse_jobs(:mailer_job)
  duplicate = Job.new(name: existing_job.name)

  assert_not duplicate.valid?
  assert_includes duplicate.errors[:name], "has already been taken"
end
```

---

### 18. Use assert_difference for testing record creation

Nest multiple `assert_difference` blocks to test multiple record types.

```ruby
test "track creates job run and operations" do
  job = FakeJob.new(job_id: "test-123", queue_name: "default")

  assert_difference -> { RailsPulse::Job.count }, 1 do
    assert_difference -> { RailsPulse::JobRun.count }, 1 do
      RailsPulse::JobRunCollector.track(job) do
        # code that creates records
        sql_operation
      end
    end
  end

  job_run = RailsPulse::JobRun.last
  assert_equal "success", job_run.status
end
```

---

### 19. Clean up test state in setup, not just teardown

Ensure a clean slate before each test.

```ruby
def setup
  ENV["TEST_TYPE"] = "functional"
  super

  # Clean up any existing data
  RailsPulse::Summary.delete_all

  @job = rails_pulse_jobs(:report_job)

  @now = Time.current
  travel_to @now
end

def teardown
  travel_back
  super
end
```

---

### 20. Use refute instead of assert_not for better readability

**✅ Good:**
```ruby
refute crumbs.first[:current]
refute_includes related_ids, @operation.id
refute_empty jobs
```

**Acceptable:**
```ruby
assert_not job.valid?  # OK when checking validity
```

---

## Test Organization

### Module Nesting

Match the application structure:

```ruby
module RailsPulse
  module Jobs
    module Cards
      class AverageDurationTest < ActiveSupport::TestCase
        # tests here
      end
    end
  end
end
```

### Fixture Declaration

Declare fixtures explicitly at the top of the test class:

```ruby
class JobTest < ActiveSupport::TestCase
  fixtures :rails_pulse_jobs, :rails_pulse_job_runs

  # tests here
end
```

---

## Assertion Guidelines

### Type Checking

Use `assert_kind_of` for type assertions:

```ruby
assert_kind_of Hash, result
assert_kind_of Array, available_queues
assert_kind_of String, label
```

### Predicate Assertions

Use predicate methods for clarity:

```ruby
assert_predicate run, :finalized?
assert_predicate run, :failure_like_status?
assert_not_nil assigns(:jobs)
assert_not_empty RailsPulse::Operation.where(job_run: run)
```

### Hash/Object Structure

Verify structure comprehensively:

```ruby
assert_kind_of Hash, result
assert_equal "jobs_total_runs", result[:id]
assert_equal "jobs", result[:context]
assert_includes result.keys, :summary
assert_includes result.keys, :chart_data

# Verify nested structure
assert_kind_of Hash, result[:chart_data]
result[:chart_data].each do |label, data|
  assert_kind_of String, label
  assert_kind_of Hash, data
  assert_includes data.keys, :value
end
```

---

## Time-Based Testing

### Freezing Time

Always freeze time in setup and unfreeze in teardown:

```ruby
def setup
  @now = Time.current
  travel_to @now
end

def teardown
  travel_back
  super
end
```

### Relative Time in Helper Methods

Use relative time calculations in helper methods:

```ruby
def create_job_summary(job:, days_ago:, count:, avg_duration:)
  period_start = days_ago.days.ago.beginning_of_day

  RailsPulse::Summary.create!(
    # ...
    period_start: period_start,
    period_end: period_start.end_of_day,
    # ...
  )
end
```

---

## Data Management

### Fixture Usage

Prefer fixtures over creating records:

```ruby
# Good - use fixture
@job = rails_pulse_jobs(:report_job)

# Less ideal - create record
@job = RailsPulse::Job.create!(name: "Test", queue_name: "default")
```

### Database Cleanup

Clean up in setup for test isolation:

```ruby
def setup
  ENV["TEST_TYPE"] = "functional"
  super

  RailsPulse::Summary.delete_all

  @job = rails_pulse_jobs(:report_job)
end
```

### Using update_columns

Use `update_columns` to bypass callbacks when setting up test data:

```ruby
run.update_columns(status: "retried", duration: 200.0)
```

---

## Edge Cases and Validation

### Comprehensive Edge Case Testing

Test all boundary conditions:

```ruby
# Edge Cases

test "handles empty collection" do
  # ...
end

test "handles nil values" do
  # ...
end

test "handles zero counts" do
  # ...
end

test "handles maximum values" do
  # ...
end

test "handles only current window data" do
  # ...
end

test "handles only previous window data" do
  # ...
end
```

### Exception Testing

Use `assert_raises` for exception testing:

```ruby
test "raises error for missing resource" do
  assert_raises ActiveRecord::RecordNotFound do
    get rails_pulse.job_path(999999)
  end
end

test "raises error for invalid arguments" do
  assert_raises ArgumentError do
    SomeService.process(nil)
  end
end
```

---

## Examples

### Complete Model Test Example

```ruby
require "test_helper"

module RailsPulse
  class JobTest < ActiveSupport::TestCase
    fixtures :rails_pulse_jobs, :rails_pulse_job_runs

    # Validations

    test "validates presence of name" do
      job = Job.new

      assert_not job.valid?
      assert_includes job.errors[:name], "can't be blank"
    end

    test "validates uniqueness of name" do
      existing_job = rails_pulse_jobs(:mailer_job)
      duplicate = Job.new(name: existing_job.name)

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    # Associations

    test "has many runs" do
      job = rails_pulse_jobs(:report_job)

      assert_respond_to job, :runs
      assert_kind_of ActiveRecord::Associations::CollectionProxy, job.runs
    end

    # Methods

    test "calculates failure rate correctly" do
      job = rails_pulse_jobs(:report_job)
      job.update!(runs_count: 100, failures_count: 25)

      assert_in_delta 25.0, job.failure_rate
    end

    test "calculates failure rate as zero when no runs" do
      job = Job.create!(name: "NewJob", queue_name: "default")

      assert_equal 0.0, job.failure_rate
    end
  end
end
```

### Complete Card Test Example

```ruby
require "test_helper"

module RailsPulse
  module Jobs
    module Cards
      class AverageDurationTest < ActiveSupport::TestCase
        fixtures :rails_pulse_jobs

        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          @job = rails_pulse_jobs(:report_job)

          RailsPulse::Summary.delete_all

          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "card returns hash with required keys" do
          card = AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "jobs_average_duration", result[:id]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
        end

        # Calculation Tests

        test "card calculates average duration for specific job" do
          # Current window (3 days ago: 100ms avg, 10 runs)
          create_job_summary(job: @job, days_ago: 3, count: 10, avg_duration: 100.0)

          # Previous window (10 days ago: 200ms avg, 5 runs)
          create_job_summary(job: @job, days_ago: 10, count: 5, avg_duration: 200.0)

          card = AverageDuration.new(job: @job)
          result = card.to_metric_card

          # Total: (100*10 + 200*5) / 15 = 133.3ms
          assert_equal "133 ms", result[:summary]

          # Trend: 100ms vs 200ms = -50%
          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        # Edge Cases

        test "card handles job with no summaries" do
          card = AverageDuration.new(job: @job)
          result = card.to_metric_card

          assert_equal "0 ms", result[:summary]
          assert_equal "move-right", result[:trend_icon]
          assert_equal "0.0%", result[:trend_amount]
        end

        private

        def create_job_summary(job:, days_ago:, count:, avg_duration:)
          period_start = days_ago.days.ago.beginning_of_day

          RailsPulse::Summary.create!(
            summarizable_type: "RailsPulse::Job",
            summarizable_id: job.id,
            period_start: period_start,
            period_end: period_start.end_of_day,
            period_type: "day",
            count: count,
            avg_duration: avg_duration
          )
        end
      end
    end
  end
end
```

---

## Helper Testing Best Practices

Helpers are pure Ruby modules that generate HTML or format data. Testing them requires following the core principle: **execute real code, not mocks**. Helpers are particularly susceptible to the "tests pass but 0% coverage" problem when over-mocked.

### 1. Use ActionView::TestCase

Helper tests should inherit from `ActionView::TestCase` and include the helper module:

```ruby
require "test_helper"

class RailsPulse::TableHelperTest < ActionView::TestCase
  include RailsPulse::TableHelper
  include RailsPulse::Engine.routes.url_helpers  # If helper generates links
  fixtures :rails_pulse_routes, :rails_pulse_queries  # If needed

  test "render_cell_content returns simple value" do
    row_data = { name: "Test Route" }
    column = { field: :name }

    result = render_cell_content(row_data, column)

    assert_equal "Test Route", result
  end
end
```

### 2. Execute helpers for real - DO NOT mock them

This is a specific application of Core Principle #1. Mocking helpers prevents their code from running.

**❌ Bad - Mocking prevents code execution:**
```ruby
test "render_cell_content with link creates link" do
  row_data = { name: "Test", path: "/test" }
  column = { field: :name, link_to: :path }

  # This prevents the real helper code from running!
  define_singleton_method(:link_to) { |text, path, opts| "<a>#{text}</a>" }

  result = render_cell_content(row_data, column)
  # Helper code never executed = 0% coverage
end
```

**✅ Good - Let helper execute for real:**
```ruby
test "render_cell_content with link creates link" do
  row_data = { name: "Test", path: "/test" }
  column = { field: :name, link_to: :path }

  # Real execution - link_to is available from ActionView::TestCase
  result = render_cell_content(row_data, column)

  assert_includes result, "Test"
  assert_includes result, "/test"
  assert_includes result, "<a"
end
```

### 3. Include route helpers when needed

If your helper generates links using route helpers (like `query_path`, `route_path`), include the engine routes:

```ruby
class RailsPulse::TableHelperTest < ActionView::TestCase
  include RailsPulse::TableHelper
  include RailsPulse::Engine.routes.url_helpers  # Required for path helpers

  test "render_cell_content with link_field for query_id creates query link" do
    row_data = { name: "SELECT * FROM users", query_id: 123 }
    column = { field: :name, link_field: :query_id }

    result = render_cell_content(row_data, column)

    assert_includes result, "SELECT * FROM users"
    assert_includes result, "queries/123"
    assert_includes result, "<a"
  end
end
```

### 4. Use real data over mocks

Use fixtures or simple Ruby hashes/arrays to provide test data:

```ruby
# ✅ Good - Real data
test "display_tag_badges handles array of tags" do
  html = display_tag_badges(["production", "urgent", "api"])

  assert_includes html, "Production"
  assert_includes html, "Urgent"
  assert_includes html, "badge"
end

# ✅ Good - Fixture data
test "operations_performance_breakdown with fixture operations" do
  request = rails_pulse_requests(:users_request_1)
  operations = request.operations

  breakdown = operations_performance_breakdown(operations)

  assert_kind_of Hash, breakdown
  assert breakdown.key?(:database)
end

# ❌ Bad - Stubbing prevents real execution
test "display_tag_badges handles array of tags" do
  stub(:display_tag_badges, "<div>badge</div>") do
    result = display_tag_badges(["test"])
    # Stub prevents actual helper code from running
  end
end
```

### 5. Test all code paths and branches

Ensure your tests exercise every branch in the helper:

```ruby
# Test the main path
test "renders percentage with plus sign when positive" do
  row_data = { change: 15.5 }
  column = { field: :change, format: :percentage }

  result = render_cell_content(row_data, column)
  assert_equal "+15.5%", result
end

# Test the else branch
test "renders percentage without plus sign when negative" do
  row_data = { change: -10.2 }
  column = { field: :change, format: :percentage }

  result = render_cell_content(row_data, column)
  assert_equal "-10.2%", result
end

# Test the boundary
test "renders percentage without sign when zero" do
  row_data = { change: 0 }
  column = { field: :change, format: :percentage }

  result = render_cell_content(row_data, column)
  assert_equal "0%", result
end
```

### 6. Organize helper tests with section comments

```ruby
class RailsPulse::TableHelperTest < ActionView::TestCase
  include RailsPulse::TableHelper
  include RailsPulse::Engine.routes.url_helpers

  # ============================================================================
  # render_cell_content Tests - Basic Values
  # ============================================================================

  test "returns simple string value" do
    # ...
  end

  # ============================================================================
  # render_cell_content Tests - Links
  # ============================================================================

  test "creates link with link_to option" do
    # ...
  end

  # ============================================================================
  # render_cell_content Tests - Formatting
  # ============================================================================

  test "formats percentage with plus sign" do
    # ...
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "handles missing field in row_data" do
    # ...
  end
end
```

### 7. Keep helper tests simple

Helpers should be pure functions with clear inputs and outputs. If a helper is complex or requires extensive context (session, params, form builders), consider:

1. Simplifying the helper by extracting logic
2. Testing it in integration/system tests where full context is available
3. Adding more unit tests for extracted private methods (tested through public API)

```ruby
# Simple helper - easy to test
def humanize_time_range(time_range_symbol)
  case time_range_symbol.to_sym
  when :last_day then "last 24 hours"
  when :last_week then "last week"
  else time_range_symbol.to_s.humanize.downcase
  end
end

# Test is straightforward
test "humanize_time_range converts symbols" do
  assert_equal "last 24 hours", humanize_time_range(:last_day)
  assert_equal "last week", humanize_time_range(:last_week)
end
```

### 8. Coverage Anti-Patterns

**Problem: Tests pass but coverage is 0%**

This happens when tests use too much mocking/stubbing. The test executes but the actual application code doesn't run. This applies to all test types, not just helpers.

**Solution: Remove mocks and use real execution**

```ruby
# Before (0% coverage):
test "icon helper renders" do
  stub(:rails_pulse_icon, "<icon>") do
    assert_equal "<icon>", rails_pulse_icon("alert")
  end
end

# After (100% coverage):
test "icon helper renders" do
  html = rails_pulse_icon("alert")

  assert_includes html, "rails-pulse-icon"
  assert_includes html, "data-controller"
  assert_includes html, "rails-pulse--icon-name-value=\"alert\""
end
```

---

## Summary Checklist

Before submitting a test file, verify:

- [ ] **Tests execute real application code (minimal mocking/stubbing)**
- [ ] Tests only public methods (no private method existence tests)
- [ ] Uses fixtures where possible
- [ ] No `rescue` blocks in tests
- [ ] All assertions are specific and meaningful
- [ ] Tests are organized with comment headers
- [ ] Test names are descriptive (Subject + Action + Context)
- [ ] Uses `assert_operator` for comparisons
- [ ] Uses `assert_includes` for collection membership
- [ ] Uses `assert_in_delta` for floating point comparisons
- [ ] Edge cases are tested (nil, empty, zero, boundaries)
- [ ] Time-based tests use `travel_to` with cleanup
- [ ] Helper methods created for repetitive setup
- [ ] Configuration changes restored with `ensure` blocks
- [ ] Complex calculations documented with comments
- [ ] Both positive and negative cases tested
- [ ] Tests pass consistently across different random seeds
- [ ] Tests include necessary dependencies (route helpers, modules, etc.)
- [ ] Coverage verified (aim for >90%)

---

## JavaScript Testing

Rails Pulse uses **Vitest + JSDOM** to unit test Stimulus controllers without a browser. These tests are fast (< 2s), run independently of Ruby, and live alongside the controller source files.

### Running JS tests

```bash
npm run test:js          # Single run (used in CI)
npm run test:js:watch    # Watch mode for development
npm run test:js:coverage # Run with V8 coverage report
```

### What is and isn't tested

Controllers with clear, mockable logic are tested here:

| Controller | What's covered |
|---|---|
| `color_scheme` | localStorage restore, light/dark toggle, custom event dispatch |
| `collapsible` | collapsed/expanded class toggling, toggle text, start state |
| `dialog` | show/showModal/close delegation, closeOnClickOutside |
| `form` | submit, cancel, preventAttachment, debounce timing |
| `series_toggle` | active state toggle, `rails-pulse:toggle-series` event detail |
| `pagination` | URL param → select sync, sessionStorage fallback, updateLimit nav |
| `chart_switcher` | default/URL-param selection, switch visibility, URL update |
| `period_selector` | active styles, inactive styles on siblings |

**Do not write JSDOM tests for**: `chart`, `index`, `flame_graph`, `popover`, `datepicker`. These rely on canvas rendering, `getBoundingClientRect`, or Flatpickr DOM manipulation that JSDOM doesn't support. Test them with system tests instead.

### Test structure

Tests live in `test/javascript/controllers/` as `*.test.js`. The shared helper is at `test/javascript/setup.js`.

```js
import { mountController } from '../setup'

// Mount a controller in a real Stimulus app; get the instance for direct calls
const { app, element, teardown } = await mountController('my-id', MyController, html)
const ctrl = app.getControllerForElementAndIdentifier(element, 'my-id')
```

`mountController` handles:
- Setting `document.body.innerHTML`
- Starting a Stimulus `Application` and registering the controller
- Waiting for the MutationObserver to fire (`nextTick`)
- Returning a `teardown()` that stops the app and clears the DOM

Always call `teardown()` in `afterEach` to prevent Stimulus app leaks between tests.

### Mocking browser globals

For controllers that read URL params or navigate, stub `window.location` with a plain object. The object **must** include `toString()` because the controller uses `new URL(window.location)`:

```js
vi.stubGlobal('location', {
  href: 'http://localhost/?limit=50',
  search: '?limit=50',
  toString() { return this.href },
})
// ... test ...
vi.unstubAllGlobals()
```

For `window.history.replaceState`, the third argument is a `URL` object — coerce it to a string before asserting:

```js
const url = String(window.history.replaceState.mock.calls[0][2])
expect(url).toContain('chart_type=throughput')
```

### IntersectionObserver / ResizeObserver

Both are polyfilled with no-op vi.fn() mocks in `test/javascript/setup.js` so controllers that reference them (e.g., `menu`) can be imported without errors.

---

## Running Tests Across Multiple Environments

RailsPulse is tested against multiple Rails versions and database adapters to ensure compatibility. Before submitting changes, verify that tests pass across all supported configurations.

### Supported Configurations

**Rails Versions**: See the `Appraisals` file in the project root for all supported Rails versions.

**Database Adapters**: SQLite3, PostgreSQL, MySQL2

### Running Tests

#### Single Database

Run tests with a specific database adapter using the `DB` environment variable:

```bash
# SQLite3 (default)
rails test

# PostgreSQL
DB=postgresql rails test

# MySQL2
DB=mysql2 rails test
```

#### Test Matrix

The `test_matrix` rake task runs the complete test suite across all combinations of Rails versions and database adapters:

```bash
rake test_matrix
```

This executes tests for:
- Each Rails version in `Appraisals`
- Each database adapter (SQLite3, PostgreSQL, MySQL2)

**Total combinations**: 6 (2 Rails versions × 3 databases)

### Database-Specific Considerations

#### PostgreSQL

Requires PostgreSQL server running locally. Configure connection with environment variables:

```bash
export POSTGRES_USERNAME=postgres
export POSTGRES_PASSWORD=postgres
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
```

#### MySQL

Requires MySQL server running locally. Configure connection with environment variables:

```bash
export MYSQL_USERNAME=root
export MYSQL_PASSWORD=root
export MYSQL_HOST=localhost
export MYSQL_PORT=3306
```

#### SQLite3

No server required. Uses in-memory database for tests by default.

### Continuous Integration

All pull requests should pass the complete test matrix. Local development can use any single database, but verify multi-database compatibility before submitting PRs.

---

## Code Coverage

RailsPulse uses SimpleCov for code coverage tracking. Coverage analysis helps identify untested code and maintain high test quality.

### Running Tests with Coverage

Enable coverage tracking by setting the `COVERAGE` environment variable:

```bash
# Run tests with coverage (SQLite3 by default)
COVERAGE=true rails test

# Or use the rake task
rake test_coverage

# With specific database
COVERAGE=true DB=postgresql rails test
```

### Viewing Coverage Reports

After running tests with coverage enabled:

1. Open `coverage/index.html` in your browser
2. Review overall coverage percentage and per-file metrics
3. Click through files to see line-by-line coverage

### Coverage Configuration

SimpleCov is configured in `.simplecov` with:

- **Minimum coverage thresholds**: 90% overall, 80% per file
- **Branch coverage enabled**: Tracks if/else branch execution
- **File tracking**: Shows files with 0% coverage (untested code)
- **Grouped reporting**: Organizes by component type (Models, Controllers, Services, etc.)
- **Parallel test support**: Each worker reports separately for accurate results

### Coverage Groups

Coverage is organized into logical groups:

- **Models**: `app/models`
- **Controllers**: `app/controllers`
- **Services**: `app/services`
- **Concerns**: `app/controllers/concerns`
- **Card Components**: `app/models/rails_pulse/*/cards`
- **Chart Components**: `app/models/rails_pulse/dashboard/charts`
- **Lib**: `lib/rails_pulse` (includes middleware adapters, configuration, etc.)
- **Generators**: `lib/generators`

### What's Excluded from Coverage

- Test code (`/test/`)
- Config files (`/config/`)
- Dummy app (`/test/dummy/`)
- Database migrations (`/db/`)

### Coverage Best Practices

1. **Run coverage regularly** during development to catch untested code early
2. **Investigate 0% coverage** files - they indicate completely untested code
3. **Check branch coverage** - 100% line coverage doesn't mean all code paths are tested
4. **Don't game the metrics** - focus on meaningful tests, not just hitting coverage targets
5. **Review coverage in PRs** - ensure new features include tests
6. **Clear coverage cache when needed** - SimpleCov merges results across runs. If coverage seems stuck, clear it:
   ```bash
   rm -rf coverage/ && COVERAGE=true rails test
   ```
7. **Watch for "tests pass but 0% coverage"** - This is usually caused by:
   - Too much mocking/stubbing (code never executes)
   - Missing module includes or dependencies
   - Tests that only check method existence, not execution
   - This applies to ALL test types: models, controllers, services, helpers, concerns

### Achieving High Coverage (>90%)

Follow these principles for any code type (models, services, helpers, controllers):

1. **Execute real code** - Minimize mocking/stubbing of your own application code
2. **Include dependencies** - Route helpers, modules, concerns that code needs
3. **Test all branches** - If/else, case statements, ternary operators, early returns
4. **Use real data** - Fixtures for models, simple data structures for helpers
5. **Test edge cases** - nil, empty, zero, boundary values

Example coverage progression for helpers:
```
Initial (with mocking):  12.9% coverage
After removing mocks:    100%  coverage
```

The same principle applies to all code: **Real execution beats mocking every time.**

### When Mocking is Appropriate

Mock external dependencies, not your own code:

**✅ Good mocking:**
- HTTP requests to third-party APIs
- External services (payment processors, email providers)
- File system operations when testing logic (not file handling)
- Time-consuming external processes

**❌ Bad mocking:**
- Your own models, services, helpers, or concerns
- Rails framework methods
- Database queries (use fixtures instead)
- Simple calculations or data transformations

### CI Integration

In CI environments, SimpleCov uses a simple text formatter. For integration with services like Codecov or Coveralls, add the appropriate formatter gem:

```ruby
# Gemfile
group :development, :test do
  gem "simplecov-cobertura", require: false  # For XML reports
end
```

Then update the formatter configuration in `.simplecov`:

```ruby
# .simplecov
if ENV["CI"]
  require "simplecov-cobertura"
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::SimpleFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ])
end
```

### Parallel Test Considerations

Coverage tracking automatically disables parallel test execution for accuracy. Each test worker gets a unique command name for proper coverage merging:

```ruby
# test/test_helper.rb
SimpleCov.command_name "test:#{Process.pid}"

# Disable parallelization when coverage is enabled
parallelize(workers: (ENV["BROWSER"] || ENV["COVERAGE"]) ? 0 : :number_of_processors)
```

When `COVERAGE=true`, tests run serially to ensure accurate coverage measurement.

---

**Last Updated:** 2026-04-08
