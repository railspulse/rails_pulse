# Loaded only when zeitwerk_test.rb declares the API acronym. The engine pins
# its own api/ directories to `Api`; a host's must still resolve to `API`.
module API
  class Ping
  end
end
