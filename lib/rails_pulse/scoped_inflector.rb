module RailsPulse
  # Zeitwerk inflector that pins the engine's own file names and defers
  # everything else to the host's inflector.
  #
  # Rails' autoloader inflector is one map for the whole application, keyed
  # only on a file's basename. Registering "api" => "Api" there would also
  # rename a host's app/controllers/api/ directory, and a host that declares
  # `inflect.acronym "API"` would then fail to find API::V1::... Checking the
  # absolute path keeps the overrides inside the engine.
  class ScopedInflector
    # @param fallback [#camelize] the inflector the autoloader had before
    # @param root [String] absolute path whose files the overrides apply to
    # @param overrides [Hash{String => String}] basename => constant name
    def initialize(fallback, root:, overrides:)
      @fallback = fallback
      @root = File.join(root.to_s, "")
      @overrides = overrides
    end

    def camelize(basename, abspath)
      if abspath.to_s.start_with?(@root) && @overrides.key?(basename)
        @overrides[basename]
      else
        @fallback.camelize(basename, abspath)
      end
    end

    # Hosts register their own overrides with
    # `Rails.autoloaders.main.inflector.inflect(...)`; those still reach the
    # inflector they were written for.
    def inflect(overrides)
      @fallback.inflect(overrides)
    end
  end
end
