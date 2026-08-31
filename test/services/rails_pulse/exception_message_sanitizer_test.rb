require "test_helper"

module RailsPulse
  class ExceptionMessageSanitizerTest < ActiveSupport::TestCase
    def setup
      ENV["TEST_TYPE"] = "unit"
      super
    end

    # Structure Tests

    test "returns the message unchanged when nothing matches a filter" do
      assert_equal "something went wrong", ExceptionMessageSanitizer.call("something went wrong")
    end

    test "truncates to 500 characters" do
      assert_operator ExceptionMessageSanitizer.call("x" * 600).length, :<=, 500
    end

    test "handles a nil message" do
      assert_equal "", ExceptionMessageSanitizer.call(nil)
    end

    # Redaction Tests

    test "strips trailing sql from a statement invalid message" do
      message = "PG::UniqueViolation: ERROR: duplicate key: INSERT INTO users (email) VALUES ('a@b.com')"

      result = ExceptionMessageSanitizer.call(message, statement_invalid: true)

      refute_includes result, "a@b.com"
      refute_includes result, "INSERT INTO"
    end

    test "redacts pg detail key clauses" do
      message = "duplicate key value violates unique constraint DETAIL: Key (email)=(user@example.com) already exists."

      result = ExceptionMessageSanitizer.call(message, statement_invalid: true)

      refute_includes result, "user@example.com"
      assert_includes result, "DETAIL: Key (…)=(…)"
    end

    test "keeps only the first line of a statement invalid message" do
      result = ExceptionMessageSanitizer.call("first line\nsecond line", statement_invalid: true)

      refute_includes result, "second line"
    end

    test "does not strip sql when the exception is not a statement invalid" do
      message = "some text: SELECT 1"

      assert_includes ExceptionMessageSanitizer.call(message), "SELECT 1"
    end

    # Edge Cases

    test "for_exception detects statement invalid exceptions" do
      exception = ActiveRecord::StatementInvalid.new("boom: DELETE FROM users")

      refute_includes ExceptionMessageSanitizer.for_exception(exception), "DELETE FROM"
    end

    test "for_exception leaves ordinary exceptions alone" do
      assert_equal "plain failure", ExceptionMessageSanitizer.for_exception(RuntimeError.new("plain failure"))
    end
  end
end
