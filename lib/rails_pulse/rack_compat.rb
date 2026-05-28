require "rack/session/cookie"

# Rails 8.1 added session.enabled? in ActionDispatch::Flash#commit_flash, but
# Rack::Session::Abstract::SessionHash (produced by Rack::Session::Cookie) does
# not define it. This shim adds the missing method so the standalone server does
# not raise NoMethodError on every request when running against a Rails 8.1 app.
unless Rack::Session::Abstract::SessionHash.method_defined?(:enabled?)
  Rack::Session::Abstract::SessionHash.define_method(:enabled?) { true }
end
