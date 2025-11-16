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

### 1. DO NOT test the existence of private methods

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

## Summary Checklist

Before submitting a test file, verify:

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

**Last Updated:** 2025-10-29
