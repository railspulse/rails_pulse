module RailsPulse
  # Recognizes a path/method against the host app's router outside a real request.
  # Host apps often constrain routes with Devise/Warden (`r.env["warden"].authenticated?`);
  # those constraints raise when warden is missing, so we stub it and try both
  # authenticated and unauthenticated.
  class RouteRecognizer
    WardenStub = Struct.new(:authenticated) do
      def authenticated?(*)
        authenticated
      end

      def authenticate?(*)
        authenticated
      end
    end

    def self.call(path, method:)
      new(path, method).call
    end

    def initialize(path, method)
      @path = path
      @method = method.to_s.upcase
    end

    def call
      return nil if @path.blank? || @method.blank?

      recognize(authenticated: true) || recognize(authenticated: false)
    end

    private

    def recognize(authenticated:)
      env = Rack::MockRequest.env_for(@path, method: @method)
      env["warden"] = WardenStub.new(authenticated)
      request = ActionDispatch::Request.new(env)

      Rails.application.routes.recognize_path_with_request(request, @path, {})
    rescue ActionController::RoutingError, ActionController::UnknownHttpMethod
      nil
    rescue NoMethodError, ArgumentError
      # Other request-env constraints that still can't run outside a real request.
      nil
    end
  end
end
