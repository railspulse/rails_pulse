FactoryBot.define do
  factory :operation, class: "RailsPulse::Operation" do
    association :request
    association :query, factory: :query
    operation_type { "sql" }
    label { "SELECT * FROM users" }
    occurred_at { Time.current }
    duration { rand(1..100) }
    start_time { rand(0..1000) }

    trait :sql do
      operation_type { "sql" }
      label { "SELECT * FROM users WHERE id = ?" }
    end

    trait :controller do
      operation_type { "controller" }
      label { "UsersController#show" }
    end

    trait :template do
      operation_type { "template" }
      label { "users/show.html.erb" }
    end

    trait :fast do
      duration { rand(1..50) }
    end

    trait :slow do
      duration { rand(100..500) }
    end

    trait :very_slow do
      duration { rand(500..2000) }
    end

    trait :with_query do
      association :query, factory: :query
    end

    trait :without_query do
      query { nil }
    end

    trait :with_request do
      association :request
    end

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

    trait :with_start_time do
      transient do
        with_start_time { 0 }
      end

      start_time { with_start_time }
    end
  end
end
