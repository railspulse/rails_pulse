module RailsPulse
  # Utility class for generating cache keys for cached components
  class ComponentCacheKey
    # Generate a cache key for a specific component type and context
    #
    # The cache key includes several parts:
    # - A namespace prefix to avoid collisions with other cached data
    # - The context (like "routes" or "route_123") to separate different views
    # - The component type (like "average_response_times") to separate different components
    # (Note: Time-based cache expiration is now handled via expires_in option)
    def self.build(id, context = nil)
      [ "rails_pulse_component", id, context ].compact
    end

    # Generate a cache expiration duration with jitter
    #
    # This returns a duration that can be used with the expires_in option.
    # We add some randomness (jitter) so all components don't expire at exactly
    # the same time, which would cause a "thundering herd" problem where all
    # components recalculate simultaneously and overwhelm the database.
    def self.cache_expires_in
      # Get the configured cache duration (e.g., 5 minutes)
      cache_duration = RailsPulse.configuration.component_cache_duration.to_i

      # Add up to 25% random jitter to spread out cache expirations
      max_jitter = (cache_duration * 0.25).to_i
      jitter = rand(max_jitter)

      # Return the base duration plus jitter
      cache_duration + jitter
    end
  end
end
