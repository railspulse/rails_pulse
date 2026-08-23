require "test_helper"

module RailsPulse
  class RouteRecognizerTest < ActiveSupport::TestCase
    test "recognizes a normal path" do
      params = RailsPulse::RouteRecognizer.call("/posts/99", method: "GET")

      assert_equal "home", params[:controller]
      assert_equal "index", params[:action]
      assert_equal "99", params[:id]
    end

    test "recognizes warden-authenticated constrained routes" do
      params = RailsPulse::RouteRecognizer.call("/warden_protected", method: "GET")

      assert_equal "home", params[:controller]
      assert_equal "index", params[:action]
    end

    test "recognizes warden-unauthenticated constrained routes" do
      params = RailsPulse::RouteRecognizer.call("/warden_public", method: "GET")

      assert_equal "home", params[:controller]
      assert_equal "index", params[:action]
    end

    test "returns nil for unknown paths" do
      assert_nil RailsPulse::RouteRecognizer.call("/ghost/route", method: "GET")
    end

    test "returns nil for blank path" do
      assert_nil RailsPulse::RouteRecognizer.call("", method: "GET")
      assert_nil RailsPulse::RouteRecognizer.call(nil, method: "GET")
    end

    test "returns nil for invalid http method" do
      assert_nil RailsPulse::RouteRecognizer.call("/posts/99", method: "NOT_A_VERB")
    end
  end
end
