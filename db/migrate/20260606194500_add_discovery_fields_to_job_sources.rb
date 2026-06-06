class AddDiscoveryFieldsToJobSources < ActiveRecord::Migration[8.1]
  def change
    add_column :job_sources, :adapter_key, :string, null: false, default: "manual_only"
    add_column :job_sources, :supports_backfill, :boolean, null: false, default: false
    add_column :job_sources, :scan_window_days, :integer, null: false, default: 20
    add_column :job_sources, :last_full_scan_at, :datetime

    add_index :job_sources, :adapter_key
    add_index :job_sources, :supports_backfill
  end
end
