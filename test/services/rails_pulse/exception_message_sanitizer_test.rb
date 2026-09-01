require "test_helper"

module RailsPulse
  class ExceptionMessageSanitizerTest < ActiveSupport::TestCase
    def setup
      ENV["TEST_TYPE"] = "unit"
      @original_filter = RailsPulse.configuration.exception_message_filter
      super
    end

    def teardown
      RailsPulse.configuration.exception_message_filter = @original_filter
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

    # StatementInvalid Redaction Tests

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

    test "redacts mysql duplicate entry values" do
      message = "Mysql2::Error: Duplicate entry 'alice@example.com' for key 'users.index_users_on_email': INSERT INTO `users` ..."

      result = ExceptionMessageSanitizer.call(message, statement_invalid: true)

      refute_includes result, "alice@example.com"
      assert_includes result, "Duplicate entry '[FILTERED]' for key 'users.index_users_on_email'"
      refute_includes result, "INSERT INTO"
    end

    test "keeps only the first line of a statement invalid message" do
      result = ExceptionMessageSanitizer.call("first line\nsecond line", statement_invalid: true)

      refute_includes result, "second line"
    end

    test "does not strip sql when the exception is not a statement invalid" do
      message = "some text: SELECT 1"

      assert_includes ExceptionMessageSanitizer.call(message), "SELECT 1"
    end

    # filter_parameters Redaction Tests
    #
    # The dummy app filters :passw, :email, :secret, :token, :_key, :crypt,
    # :salt, :certificate, :otp, :ssn, :cvv, :cvc — the Rails defaults.

    test "redacts key=value pairs whose key matches filter_parameters" do
      result = ExceptionMessageSanitizer.call("login failed password=hunter2 for bob")

      refute_includes result, "hunter2"
      assert_equal "login failed password=[FILTERED] for bob", result
    end

    test "redacts key: value pairs" do
      result = ExceptionMessageSanitizer.call("Stripe::CardError: token: sk_live_abc123 was declined")

      refute_includes result, "sk_live_abc123"
      assert_includes result, "token: [FILTERED]"
    end

    test "redacts json style quoted pairs" do
      result = ExceptionMessageSanitizer.call(%q(JSON::ParserError near {"email":"alice@example.com","plan":"pro"}))

      refute_includes result, "alice@example.com"
      assert_includes result, %q("email":[FILTERED])
      assert_includes result, %q("plan":"pro")
    end

    test "redacts hash rocket pairs" do
      result = ExceptionMessageSanitizer.call(%q(bad args {"api_key" => "abc123", "id" => 5}))

      refute_includes result, "abc123"
      assert_includes result, %q("id" => 5)
    end

    test "redacts values inside query strings" do
      result = ExceptionMessageSanitizer.call("Faraday::ClientError: GET https://api.example.com/v1/me?token=abc&page=2 returned 401")

      refute_includes result, "abc"
      assert_includes result, "token=[FILTERED]"
      assert_includes result, "page=2"
    end

    test "applies filter_parameters substring matching like rails does" do
      result = ExceptionMessageSanitizer.call("csrf_token=xyz and passwd=123")

      refute_includes result, "xyz"
      refute_includes result, "123"
    end

    test "leaves pairs whose key does not match filter_parameters alone" do
      message = "Couldn't find User with 'id'=42 and status=active"

      assert_equal message, ExceptionMessageSanitizer.call(message)
    end

    test "redacts quoted values that contain spaces" do
      result = ExceptionMessageSanitizer.call(%q(secret="hello world" ok))

      assert_equal %q(secret=[FILTERED] ok), result
    end

    test "does not treat urls or times as pairs" do
      message = "timeout at 12:30 fetching https://example.com/health"

      assert_equal message, ExceptionMessageSanitizer.call(message)
    end

    test "filters the whole message when the host filters a key named message" do
      with_filter_parameters([ :message ]) do
        assert_equal "[FILTERED]", ExceptionMessageSanitizer.call("password=hunter2")
      end
    end

    test "leaves messages untouched when filter_parameters is empty" do
      with_filter_parameters([]) do
        assert_equal "password=hunter2", ExceptionMessageSanitizer.call("password=hunter2")
      end
    end

    # exception_message_filter Hook Tests

    test "applies the configured exception_message_filter" do
      RailsPulse.configuration.exception_message_filter = ->(message, _exception) { message.gsub(/\d{4}/, "####") }

      assert_equal "card ending ####", ExceptionMessageSanitizer.call("card ending 4242")
    end

    test "supports a single argument exception_message_filter" do
      RailsPulse.configuration.exception_message_filter = ->(message) { message.upcase }

      assert_equal "BOOM", ExceptionMessageSanitizer.call("boom")
    end

    test "passes the exception to a two argument filter" do
      seen = nil
      RailsPulse.configuration.exception_message_filter = ->(message, exception) { seen = exception; message }
      error = RuntimeError.new("boom")

      ExceptionMessageSanitizer.for_exception(error)

      assert_same error, seen
    end

    test "runs the hook after the built-in redaction" do
      RailsPulse.configuration.exception_message_filter = ->(message, _) { message.sub("[FILTERED]", "<redacted>") }

      assert_equal "password=<redacted>", ExceptionMessageSanitizer.call("password=hunter2")
    end

    test "fails closed when the hook raises" do
      RailsPulse.configuration.exception_message_filter = ->(_message, _) { raise "hook broke" }

      assert_equal "[FILTERED]", ExceptionMessageSanitizer.call("password=hunter2 secret stuff")
    end

    test "coerces a non string hook result" do
      RailsPulse.configuration.exception_message_filter = ->(_message, _) { nil }

      assert_equal "", ExceptionMessageSanitizer.call("boom")
    end

    # Edge Cases

    test "for_exception detects statement invalid exceptions" do
      exception = ActiveRecord::StatementInvalid.new("boom: DELETE FROM users")

      refute_includes ExceptionMessageSanitizer.for_exception(exception), "DELETE FROM"
    end

    test "for_exception leaves ordinary exceptions alone" do
      assert_equal "plain failure", ExceptionMessageSanitizer.for_exception(RuntimeError.new("plain failure"))
    end

    test "for_exception redacts filtered pairs in ordinary exceptions" do
      exception = RuntimeError.new("auth failed token=abc")

      assert_equal "auth failed token=[FILTERED]", ExceptionMessageSanitizer.for_exception(exception)
    end

    private

    def with_filter_parameters(patterns)
      original = Rails.application.config.filter_parameters
      Rails.application.config.filter_parameters = patterns
      yield
    ensure
      Rails.application.config.filter_parameters = original
    end
  end
end
