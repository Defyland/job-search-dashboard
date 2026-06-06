class CreateDiscoveredJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :discovered_jobs do |t|
      t.references :search_run, null: false, foreign_key: true
      t.references :source_scan, null: false, foreign_key: true
      t.references :job_source, null: false, foreign_key: true
      t.references :job, foreign_key: true
      t.integer :classification, null: false, default: 0
      t.string :title
      t.string :company_name
      t.string :apply_url
      t.string :canonical_url
      t.string :source_url
      t.string :external_job_id
      t.string :fingerprint, null: false
      t.string :remote_text
      t.string :location_text
      t.string :seniority, null: false, default: "senior"
      t.text :reason
      t.text :exclusion_reason
      t.integer :score, null: false, default: 0
      t.datetime :published_at
      t.string :posted_text
      t.text :stack_tags, null: false, default: [], array: true
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :discovered_jobs, [ :source_scan_id, :fingerprint ], unique: true
    add_index :discovered_jobs, :classification
    add_index :discovered_jobs, :canonical_url
  end
end
