# Add index to rails_pulse_requests.request_uuid for efficient lookups
class AddIndexToRequestUuid < ActiveRecord::Migration[7.0]
  def up
    unless index_exists?(:rails_pulse_requests, :request_uuid)
      add_index :rails_pulse_requests, :request_uuid, unique: true, name: "index_rails_pulse_requests_on_request_uuid"
    end
  end

  def down
    if index_exists?(:rails_pulse_requests, :request_uuid)
      remove_index :rails_pulse_requests, name: "index_rails_pulse_requests_on_request_uuid"
    end
  end
end
