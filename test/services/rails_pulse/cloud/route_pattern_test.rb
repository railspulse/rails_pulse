require "test_helper"

module RailsPulse
  module Cloud
    class RoutePatternTest < ActiveSupport::TestCase
      setup do
        routes = ActionDispatch::Routing::RouteSet.new
        routes.draw do
          get "/users/:user_id/posts/:id", to: "posts#show"
          get "/posts(/:page)", to: "posts#index"
          get "/:locale/about", to: "pages#about"
          get "/reports/:id(.:format)", to: "reports#show"
          get "*slug", to: "pages#show"
        end
        @patterns = RoutePattern.new(routes.routes)
      end

      # Calculation Tests

      test "sends the router's pattern when two parameters share a value" do
        assert_equal "/users/:user_id/posts/:id", @patterns.path_for("/users/5/posts/5", "posts#show")
      end

      test "sends the glob's pattern rather than the captured path" do
        assert_equal "/*slug", @patterns.path_for("/docs/jane-doe/getting-started", "pages#show")
      end

      test "expands optional segments" do
        assert_equal "/posts/:page", @patterns.path_for("/posts/:page", "posts#index")
        assert_equal "/posts", @patterns.path_for("/posts", "posts#index")
      end

      test "a stored literal under a dynamic segment takes the parameter's name" do
        assert_equal "/:locale/about", @patterns.path_for("/en/about", "pages#about")
      end

      test "a format extension on the stored path matches the pattern without it" do
        assert_equal "/reports/:id", @patterns.path_for("/reports/:id.json", "reports#show")
      end

      # Edge Cases

      test "without a pattern for the action, segments that do not read as code are replaced" do
        path = @patterns.path_for("/admin/jane.doe@example.com/42/:id/settings", "admin/users#show")

        assert_equal "/admin/*/*/:id/settings", path
      end

      test "without a pattern, a trailing slash and the root survive" do
        assert_equal "/admin/", @patterns.path_for("/admin/", "nothing#here")
        assert_equal "/", @patterns.path_for("/", "nothing#here")
      end

      test "a pattern with a different literal does not match" do
        assert_equal "/teams/*/posts/:id", @patterns.path_for("/teams/5/posts/:id", "posts#show")
      end
    end
  end
end
