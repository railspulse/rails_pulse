# The writer heartbeat fixtures are stamped relative to the moment fixtures
# load, and a writer only counts as live for WriterHeartbeat::LIVE_WINDOW. A
# test that runs minutes into a serial suite would otherwise find them stale.
module HeartbeatFixtureHelpers
  # Moves the clock back to when the heartbeat fixtures were loaded: the
  # newest one, web_one_latest, is stamped 30 seconds before that.
  def travel_to_heartbeat_fixtures
    travel_to rails_pulse_events(:web_one_latest).occurred_at + 30.seconds
  end
end
