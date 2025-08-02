FactoryBot.define do
  factory :query, class: "RailsPulse::Query" do
    sequence(:normalized_sql) { |n| "SELECT * FROM table_#{Process.pid}_#{n} WHERE id = ?" }

    trait :select_query do
      normalized_sql { "SELECT * FROM users WHERE id = ?" }
    end

    trait :insert_query do
      normalized_sql { "INSERT INTO users (name, email) VALUES (?, ?)" }
    end

    trait :update_query do
      normalized_sql { "UPDATE users SET name = ? WHERE id = ?" }
    end

    trait :delete_query do
      normalized_sql { "DELETE FROM users WHERE id = ?" }
    end

    trait :complex_query do
      normalized_sql { "SELECT u.*, p.* FROM users u LEFT JOIN profiles p ON u.id = p.user_id WHERE u.created_at > ?" }
    end

    # Performance traits
    trait :fast do
      # Fast queries don't need specific duration setup
    end

    trait :slow do
      # Slow queries don't need specific duration setup
    end

    trait :very_slow do
      # Very slow queries don't need specific duration setup
    end

    trait :critical do
      # Critical queries don't need specific duration setup
    end

    # Alias traits for consistency with factories_test.rb
    trait :select do
      normalized_sql { "SELECT * FROM users WHERE id = ?" }
    end

    trait :insert do
      normalized_sql { "INSERT INTO users (name, email) VALUES (?, ?)" }
    end

    trait :update do
      normalized_sql { "UPDATE users SET name = ? WHERE id = ?" }
    end

    trait :delete do
      normalized_sql { "DELETE FROM users WHERE id = ?" }
    end

    # Realistic SQL variety for bulk testing
    trait :realistic_sql do
      sequence(:normalized_sql) do |n|
        table = %w[users posts comments orders products categories].sample
        case n % 5
        when 0 then "SELECT * FROM #{table} WHERE id = ? -- #{n}"
        when 1 then "SELECT COUNT(*) FROM #{table} GROUP BY created_at -- #{n}"
        when 2 then "INSERT INTO #{table} (name, email) VALUES (?, ?) -- #{n}"
        when 3 then "UPDATE #{table} SET updated_at = ? WHERE id = ? -- #{n}"
        else "DELETE FROM #{table} WHERE archived = true -- #{n}"
        end
      end
    end

    trait :complex_realistic do
      sequence(:normalized_sql) do |n|
        [
          "SELECT u.*, p.* FROM users u LEFT JOIN profiles p ON u.id = p.user_id WHERE u.created_at > ? -- #{n}",
          "SELECT COUNT(*) FROM orders o JOIN users u ON o.user_id = u.id WHERE o.status = ? -- #{n}",
          "UPDATE posts SET view_count = view_count + ? WHERE published = true -- #{n}",
          "SELECT AVG(rating) FROM reviews WHERE product_id IN (SELECT id FROM products WHERE category = ?) -- #{n}"
        ][n % 4]
      end
    end
  end
end
