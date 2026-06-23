class AddRadarOrderIndexToJobMatches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :job_matches,
              [ :search_profile_id, :user_state, :first_seen_at, :id ],
              order: { first_seen_at: :desc, id: :desc },
              algorithm: :concurrently,
              name: "index_job_matches_on_radar_order"
  end
end
