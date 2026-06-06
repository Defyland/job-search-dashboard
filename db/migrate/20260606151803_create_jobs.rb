class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.references :job_source, null: false, foreign_key: true
      t.string :title, null: false
      t.string :company_name, null: false
      t.string :apply_url, null: false
      t.string :canonical_url, null: false
      t.string :source_url
      t.string :ats_name
      t.string :external_job_id
      t.string :remote_text
      t.string :location_text
      t.string :seniority, null: false, default: "senior"
      t.integer :match_strength, null: false, default: 0
      t.integer :user_state, null: false, default: 0
      t.integer :lifecycle_state, null: false, default: 0
      t.text :reason, null: false
      t.integer :score, null: false, default: 0
      t.string :posted_text
      t.datetime :published_at
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :last_validated_at, null: false
      t.string :fingerprint, null: false
      t.text :stack_tags, array: true, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :jobs, :fingerprint, unique: true
    add_index :jobs, :canonical_url, unique: true
    add_index :jobs, :external_job_id
    add_index :jobs, %i[lifecycle_state user_state match_strength]
    add_index :jobs, :last_seen_at
  end
end
