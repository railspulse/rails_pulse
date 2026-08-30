class AddLocationToExceptionGroups < ActiveRecord::Migration[7.0]
  def change
    # Guard on table existence — users who deleted the exceptions migration
    # per the upgrade generator's advice won't have the table yet.
    return unless table_exists?(:rails_pulse_exception_groups)

    unless column_exists?(:rails_pulse_exception_groups, :location)
      add_column :rails_pulse_exception_groups, :location, :string,
        comment: "Relative first app-code frame, e.g. app/models/user.rb#save"
    end
  end
end
