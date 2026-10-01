require "test_helper"

module RailsPulse
  module Api
    module V1
      class ExceptionGroupSerializerTest < ActiveSupport::TestCase
        fixtures :rails_pulse_exception_groups

        test "serializes exception group fields" do
          group = rails_pulse_exception_groups(:resolved_group)
          result = ExceptionGroupSerializer.serialize(group)

          assert_equal group.id, result[:id]
          assert_equal group.fingerprint, result[:fingerprint]
          assert_equal "ArgumentError", result[:exception_class]
          assert_equal "app/models/order.rb#save", result[:location]
          assert_equal "bad argument", result[:message]
          assert_equal "resolved", result[:status]
          assert_equal 2, result[:occurrence_count]
          assert_equal group.first_seen_at, result[:first_seen_at]
          assert_equal group.last_seen_at, result[:last_seen_at]
          assert_equal group.resolved_at, result[:resolved_at]
          refute result[:preserve]
        end

        test "returns a hash with exactly the expected keys" do
          result = ExceptionGroupSerializer.serialize(rails_pulse_exception_groups(:record_not_found))

          assert_equal %i[id fingerprint exception_class location message status occurrence_count
                          first_seen_at last_seen_at resolved_at preserve], result.keys
        end
      end
    end
  end
end
