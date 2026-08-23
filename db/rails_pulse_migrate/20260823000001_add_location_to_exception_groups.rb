class AddLocationToExceptionGroups < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_pulse_exception_groups, :location)
      add_column :rails_pulse_exception_groups, :location, :string,
        comment: "Relative first app-code frame, e.g. app/models/user.rb#save"
    end
  end
end
