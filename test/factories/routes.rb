FactoryBot.define do
  factory :route, class: "RailsPulse::Route" do
    # Ensure tables exist before creating route
    before(:create) do |route|
      DatabaseHelpers.ensure_test_tables_exist if defined?(DatabaseHelpers)
    end

    sequence(:path) { |n| "/api/endpoint_#{Process.pid}_#{n}" }
    add_attribute(:method) { "GET" }

    trait :post do
      add_attribute(:method) { "POST" }
    end

    trait :put do
      add_attribute(:method) { "PUT" }
    end

    trait :delete do
      add_attribute(:method) { "DELETE" }
    end

    trait :api do
      sequence(:path) { |n| "/api/v1/resources/#{n}" }
    end

    trait :admin do
      sequence(:path) { |n| "/admin/#{n}" }
    end

    # Performance-related traits
    trait :fast_endpoint do
      sequence(:path) { |n| "/fast/endpoint_#{n}" }
    end

    trait :slow_endpoint do
      sequence(:path) { |n| "/slow/endpoint_#{n}" }
    end

    trait :very_slow_endpoint do
      sequence(:path) { |n| "/very_slow/endpoint_#{n}" }
    end

    trait :critical_endpoint do
      sequence(:path) { |n| "/critical/api/#{n}" }
    end

    # Realistic paths using Faker
    trait :realistic do
      path { "/#{Faker::Internet.slug}" }
    end

    trait :rest_api do
      sequence(:path) { |n| "/api/v1/#{Faker::Lorem.word.pluralize}/#{n}" }
    end

    # Bulk data generation helpers
    trait :varied_method do
      add_attribute(:method) { %w[GET POST PUT DELETE PATCH].sample }
    end

    trait :realistic_api do
      add_attribute(:method) { %w[GET POST PUT DELETE].sample }
      sequence(:path) do |n|
        resource = %w[users posts comments orders products categories].sample
        "/api/v1/#{resource}/#{n}"
      end
    end
  end
end
