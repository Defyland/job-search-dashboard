class CreateSourceScans < ActiveRecord::Migration[8.1]
  def change
    create_table :source_scans do |t|
      t.references :search_run, null: false, foreign_key: true
      t.references :job_source, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :pages_scanned, null: false, default: 0
      t.integer :candidates_seen, null: false, default: 0
      t.integer :accepted_count, null: false, default: 0
      t.integer :borderline_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.integer :expired_count, null: false, default: 0
      t.string :cursor
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :source_scans, [ :search_run_id, :job_source_id ], unique: true
    add_index :source_scans, :status
  end
end
