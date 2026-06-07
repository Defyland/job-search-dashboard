class CreateSearchProfilesAndJobMatches < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationJob < ActiveRecord::Base
    self.table_name = "jobs"
  end

  class MigrationSearchProfile < ActiveRecord::Base
    self.table_name = "search_profiles"
  end

  class MigrationJobMatch < ActiveRecord::Base
    self.table_name = "job_matches"
  end

  def up
    create_table :search_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :active, null: false, default: true
      t.text :target_stacks, null: false, array: true, default: []
      t.text :target_titles, null: false, array: true, default: []
      t.text :seniority_terms, null: false, array: true, default: []
      t.text :location_terms, null: false, array: true, default: []
      t.text :negative_terms, null: false, array: true, default: []
      t.boolean :required_remote, null: false, default: true
      t.boolean :include_women_only, null: false, default: false
      t.integer :scan_window_days, null: false, default: 20
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :search_profiles, [ :user_id, :slug ], unique: true
    add_index :search_profiles, :active

    create_table :job_matches do |t|
      t.references :search_profile, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true
      t.integer :match_strength, null: false, default: 0
      t.integer :user_state, null: false, default: 0
      t.integer :score, null: false, default: 0
      t.text :reason, null: false, default: ""
      t.string :seniority, null: false, default: "senior"
      t.text :stack_tags, null: false, array: true, default: []
      t.text :eligibility_flags, null: false, array: true, default: []
      t.jsonb :raw_decision, null: false, default: {}
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :last_validated_at, null: false

      t.timestamps
    end

    add_index :job_matches, [ :search_profile_id, :job_id ], unique: true
    add_index :job_matches, [ :match_strength, :user_state ]
    add_index :job_matches, :last_seen_at

    backfill_default_profile
  end

  def down
    drop_table :job_matches
    drop_table :search_profiles
  end

  private
    def backfill_default_profile
      user = MigrationUser.order(:id).first
      return unless user

      timestamp = Time.current
      profile = MigrationSearchProfile.create!(
        user_id: user.id,
        name: "Senior Ruby/Rails/React Remote BR/LatAm",
        slug: "senior-ruby-rails-react-remote-br-latam",
        active: true,
        target_stacks: [ "ruby", "ruby on rails", "rails", "react", "react native", "frontend", "fullstack" ],
        target_titles: [ "software engineer", "engenheiro de software", "frontend", "backend", "fullstack", "developer", "desenvolvedor" ],
        seniority_terms: [ "senior", "sênior", "sr", "staff" ],
        location_terms: [ "remoto", "remote", "home office", "brasil", "brazil", "latam" ],
        negative_terms: [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio" ],
        required_remote: true,
        include_women_only: false,
        scan_window_days: 20,
        settings: {},
        created_at: timestamp,
        updated_at: timestamp
      )

      MigrationJob.find_each do |job|
        seen_at = job.last_seen_at || job.created_at || timestamp
        MigrationJobMatch.create!(
          search_profile_id: profile.id,
          job_id: job.id,
          match_strength: job.match_strength || 0,
          user_state: job.user_state || 0,
          score: job.score || 0,
          reason: job.reason.to_s,
          seniority: job.seniority.presence || "senior",
          stack_tags: Array(job.stack_tags),
          eligibility_flags: [],
          raw_decision: { migrated_from_job: true },
          first_seen_at: job.first_seen_at || seen_at,
          last_seen_at: seen_at,
          last_validated_at: job.last_validated_at || seen_at,
          created_at: timestamp,
          updated_at: timestamp
        )
      end
    end
end
