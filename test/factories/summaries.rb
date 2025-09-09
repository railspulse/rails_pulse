FactoryBot.define do
  factory :summary, class: "RailsPulse::Summary" do
    # Ensure tables exist before creating summary
    before(:create) do |summary|
      DatabaseHelpers.ensure_test_tables_exist if defined?(DatabaseHelpers)
    end

    period_type { "hour" }
    sequence(:period_start) { |n| n.hours.ago.beginning_of_hour }
    period_end { period_start.end_of_hour }
    # Default to overall request summary
    summarizable_type { "RailsPulse::Request" }
    summarizable_id { 0 }
    count { rand(10..100) }
    avg_duration { rand(50.0..200.0) }
    max_duration { rand(200.0..500.0) }
    error_count { rand(0..5) }
    success_count { count - error_count }

    trait :hour do
      period_type { "hour" }
      period_start { 1.hour.ago.beginning_of_hour }
      period_end { 1.hour.ago.end_of_hour }
    end

    trait :day do
      period_type { "day" }
      period_start { 1.day.ago.beginning_of_day }
      period_end { 1.day.ago.end_of_day }
    end

    trait :week do
      period_type { "week" }
      period_start { 1.week.ago.beginning_of_week }
      period_end { 1.week.ago.end_of_week }
    end

    trait :month do
      period_type { "month" }
      period_start { 1.month.ago.beginning_of_month }
      period_end { 1.month.ago.end_of_month }
    end

    trait :for_route do
      association :summarizable, factory: :route
      summarizable_type { "RailsPulse::Route" }
    end

    trait :for_query do
      association :summarizable, factory: :query
      summarizable_type { "RailsPulse::Query" }
    end

    trait :for_requests do
      summarizable_type { "RailsPulse::Request" }
      summarizable_id { 0 } # Overall request summaries use ID 0
    end

    trait :overall_requests do
      summarizable_type { "RailsPulse::Request" }
      summarizable_id { 0 }
    end

    trait :high_volume do
      count { rand(500..1000) }
    end

    trait :low_volume do
      count { rand(1..10) }
    end

    trait :fast do
      avg_duration { rand(10.0..50.0) }
      max_duration { rand(50.0..100.0) }
    end

    trait :slow do
      avg_duration { rand(200.0..500.0) }
      max_duration { rand(500.0..1000.0) }
    end

    trait :with_errors do
      error_count { rand(5..20) }
      success_count { count - error_count }
    end

    trait :no_errors do
      error_count { 0 }
      success_count { count }
    end

    # Time-based traits for chart testing
    trait :at_time do
      transient do
        at_time { Time.current }
        period_duration { "hour" }
      end

      period_type { period_duration }
      period_start do
        case period_duration
        when "hour" then at_time.beginning_of_hour
        when "day" then at_time.beginning_of_day
        when "week" then at_time.beginning_of_week
        when "month" then at_time.beginning_of_month
        end
      end
      period_end do
        case period_duration
        when "hour" then at_time.end_of_hour
        when "day" then at_time.end_of_day
        when "week" then at_time.end_of_week
        when "month" then at_time.end_of_month
        end
      end
    end
  end
end
