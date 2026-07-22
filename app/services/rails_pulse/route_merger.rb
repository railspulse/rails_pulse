module RailsPulse
  # Merges source into target: combine http_methods, reassign requests, destroy source.
  # Used when two routes would collide on the unique [controller_action, path] index.
  class RouteMerger
    def self.call(target:, source:)
      new(target, source).call
    end

    def initialize(target, source)
      @target = target
      @source = source
    end

    def call
      return if @target.id == @source.id

      @source.http_methods_list.each { |m| @target.add_http_method(m) }
      RailsPulse::Route.transaction do
        @source.requests.update_all(route_id: @target.id)
        @source.destroy!
      end
    end
  end
end
