class AddExpiryToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :expires_at, :datetime
    add_column :sessions, :last_used_at, :datetime

    Session.update_all("expires_at = created_at + interval '30 days'")
  end

  def down
    remove_column :sessions, :last_used_at
    remove_column :sessions, :expires_at
  end
end
