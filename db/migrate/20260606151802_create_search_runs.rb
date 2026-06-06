class CreateSearchRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :search_runs do |t|
      t.integer :trigger_source, null: false, default: 0
      t.string :window_label, null: false, default: "24h"
      t.integer :status, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :imported_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :expired_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.jsonb :summary, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :search_runs, :started_at
    add_index :search_runs, :status
  end
end
