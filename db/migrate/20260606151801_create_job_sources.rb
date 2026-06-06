class CreateJobSources < ActiveRecord::Migration[8.1]
  def change
    create_table :job_sources do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :source_kind, null: false, default: 0
      t.string :base_url
      t.string :host, null: false
      t.integer :priority, null: false, default: 100
      t.boolean :enabled, null: false, default: true
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :job_sources, :slug, unique: true
    add_index :job_sources, :host
    add_index :job_sources, :enabled
  end
end
