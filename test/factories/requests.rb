FactoryBot.define do
  factory :request, class: "RailsPulse::Request" do
    # Ensure tables exist before creating request
    before(:create) do |request|
      DatabaseHelpers.ensure_test_tables_exist if defined?(DatabaseHelpers)
    end

    association :route
    occurred_at { Time.current }
    duration { rand(50..200) }
    status { 200 }
    is_error { false }
    sequence(:request_uuid) { |n| "uuid-#{Process.pid}-#{n}-#{SecureRandom.hex(8)}" }

    trait :fast do
      duration { rand(1..99) }
    end

    trait :slow do
      duration { rand(100..500) }
    end

    trait :very_slow do
      duration { rand(500..2000) }
    end

    trait :critical do
      duration { rand(2000..5000) }
    end

    trait :error do
      is_error { true }
      status { [ 400, 404, 422, 500 ].sample }
    end

    trait :server_error do
      is_error { true }
      status { [ 500, 502, 503, 504 ].sample }
    end

    trait :client_error do
      is_error { true }
      status { [ 400, 401, 403, 404, 422 ].sample }
    end

    trait :today do
      occurred_at { Time.current.beginning_of_day + rand(24).hours }
    end

    trait :yesterday do
      occurred_at { 1.day.ago.beginning_of_day + rand(24).hours }
    end

    trait :this_week do
      occurred_at { rand(7).days.ago.beginning_of_day + rand(24).hours }
    end

    trait :last_week do
      occurred_at { (rand(7) + 7).days.ago.beginning_of_day + rand(24).hours }
    end

    # Chart-specific factory for creating requests at specific times
    factory :chart_request do
      trait :at_time do
        transient do
          at_time { Time.current }
        end

        occurred_at { at_time }
      end

      trait :with_duration do
        transient do
          with_duration { 100 }
        end

        duration { with_duration }
      end
    end

    # Time-based sequence helpers
    trait :hourly_sequence do
      transient do
        hour_offset { 0 }
      end

      occurred_at { hour_offset.hours.ago }
    end

    trait :daily_sequence do
      transient do
        day_offset { 0 }
      end

      occurred_at { day_offset.days.ago.beginning_of_day + rand(24).hours }
    end

    # Realistic request data using Faker
    trait :realistic do
      request_uuid { Faker::Internet.uuid }
      duration { Faker::Number.between(from: 10, to: 1000) }
      status { [ 200, 201, 204, 400, 404, 500 ].sample }
    end

    # Performance distribution for realistic load testing
    trait :performance_varied do
      duration do
        case rand(10)
        when 0..5 then rand(10..99)    # 60% fast
        when 6..7 then rand(100..499)  # 20% medium
        when 8 then rand(500..999)     # 10% slow
        else rand(1000..3000)          # 10% very slow
        end
      end
      status do
        case rand(10)
        when 0 then [ 400, 404, 422 ].sample  # 10% client errors
        when 1 then [ 500, 502, 503 ].sample  # 10% server errors
        else 200                             # 80% success
        end
      end
      is_error { status >= 400 }
    end

    # Time-based bulk generation
    trait :spread_over_week do
      transient do
        week_start { 1.week.ago }
      end
      occurred_at { week_start + rand(7.days).seconds }
    end

    trait :spread_over_day do
      transient do
        day_start { 1.day.ago }
      end
      occurred_at { day_start + rand(24.hours).seconds }
    end
  end
end
