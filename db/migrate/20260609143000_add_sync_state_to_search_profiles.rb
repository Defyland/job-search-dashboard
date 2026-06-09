class AddSyncStateToSearchProfiles < ActiveRecord::Migration[8.1]
  def change
    change_table :search_profiles, bulk: true do |t|
      t.integer :sync_state, default: 0, null: false
      t.datetime :last_sync_requested_at
      t.datetime :last_synced_at
      t.text :last_sync_error
    end
  end
end
