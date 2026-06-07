class AddLastCodexCheckedAtToJobSources < ActiveRecord::Migration[8.1]
  def change
    add_column :job_sources, :last_codex_checked_at, :datetime
    add_index :job_sources, :last_codex_checked_at
  end
end
