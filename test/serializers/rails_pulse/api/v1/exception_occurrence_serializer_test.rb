require "test_helper"

module RailsPulse
  module Api
    module V1
      class ExceptionOccurrenceSerializerTest < ActiveSupport::TestCase
        fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

        test "serializes occurrence fields including the parsed backtrace and params" do
          occurrence = rails_pulse_exception_occurrences(:occurrence_one)
          result = ExceptionOccurrenceSerializer.serialize(occurrence)

          assert_equal occurrence.id, result[:id]
          assert_equal "ActiveRecord::RecordNotFound", result[:exception_class]
          assert_equal "GET", result[:request_method]
          assert_equal "/posts/999", result[:request_url]
          assert_equal({ "id" => "999", "controller" => "posts", "action" => "show" }, result[:request_params])
          assert_equal "abc1234", result[:deploy_sha]
          assert_equal 2, result[:backtrace].size
          assert_equal "app/controllers/posts_controller.rb", result[:backtrace].first["file"]
        end

        test "returns nil params for an occurrence without any and exactly the expected keys" do
          result = ExceptionOccurrenceSerializer.serialize(rails_pulse_exception_occurrences(:occurrence_zero_division))

          assert_nil result[:request_params]
          assert_nil result[:request_url]
          assert_equal %i[id exception_class message occurred_at request_method request_url request_params
                          environment deploy_sha backtrace], result.keys
        end
      end
    end
  end
end
