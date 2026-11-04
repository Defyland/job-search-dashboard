require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "normalizes urls" do
    job = jobs(:react_role)
    job.apply_url = "https://example.com/"
    job.canonical_url = "https://example.com/path/"
    job.save!

    assert_equal("https://example.com", job.apply_url)
    assert_equal("https://example.com/path", job.canonical_url)
  end

  test "safe apply url keeps regular http urls" do
    job = jobs(:react_role)
    job.apply_url = "https://example.com/jobs/123"

    assert_equal "https://example.com/jobs/123", job.safe_apply_url
  end

  test "safe apply url rejects invalid or unsafe schemes" do
    job = jobs(:react_role)

    job.apply_url = "javascript:alert(1)"
    assert_nil job.safe_apply_url

    job.apply_url = "data:text/html;base64,abcd"
    assert_nil job.safe_apply_url

    job.apply_url = "not a url"
    assert_nil job.safe_apply_url
  end

  test "safe canonical url only keeps http urls" do
    job = jobs(:react_role)
    job.canonical_url = "https://example.com/jobs/123"
    assert_equal "https://example.com/jobs/123", job.safe_canonical_url

    job.canonical_url = "javascript:alert(1)"
    assert_nil job.safe_canonical_url

    job.canonical_url = "not a url"
    assert_nil job.safe_canonical_url
  end

  test "infers contract type from raw payload" do
    job = jobs(:react_role)
    job.raw_payload = { employmentType: "contractor" }
    job.save!

    assert_predicate job.reload, :contract_type_pj?
  end

  test "market enum persists unknown national and international as 0 1 2" do
    assert_equal({ "unknown" => 0, "national" => 1, "international" => 2 }, Job.markets)
  end

  test "classifies market on save from location and remote text" do
    job = jobs(:react_role)
    job.location_text = "Portugal"
    job.remote_text = "Remote"
    job.save!

    assert_predicate job.reload, :market_international?
  end

  test "save reclassifies an existing job market" do
    job = jobs(:react_role)
    assert_predicate job, :market_national?

    job.location_text = "Worldwide"
    job.save!
    assert_predicate job.reload, :market_international?

    job.location_text = ""
    job.remote_text = "Trabalho remoto"
    job.save!
    assert_predicate job.reload, :market_unknown?
  end

  test "create classifies market from location and remote text" do
    job = Job.create!(
      job_source: job_sources(:gupy),
      title: "Platform Engineer",
      company_name: "Acme",
      apply_url: "https://acme.example.com/jobs/platform",
      canonical_url: "https://acme.example.com/jobs/platform",
      source_url: "https://acme.example.com/jobs/platform",
      fingerprint: "acme::platform engineer::acme.example.com::platform",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      last_validated_at: Time.current,
      location_text: "Sao Paulo",
      remote_text: "Remote"
    )

    assert_predicate job.reload, :market_national?
  end

  test "title and raw payload mentioning Brazil do not set market" do
    job = jobs(:react_role)
    job.title = "Brazil Engineer"
    job.location_text = nil
    job.remote_text = nil
    job.raw_payload = { description: "Trabalho remoto no Brasil, Brazil", location: "Brazil" }
    job.save!

    assert_predicate job.reload, :market_unknown?
  end

  test "placeholder sem data publica is unknown" do
    job = jobs(:react_role)
    job.location_text = "Sem data pública"
    job.remote_text = nil
    job.save!

    assert_predicate job.reload, :market_unknown?
  end

  test "add market migration backfills existing rows with literal expectations" do
    connection = ActiveRecord::Base.connection
    gupy_id = job_sources(:gupy).id

    ActiveRecord::Migration.suppress_messages { load_market_migration.new.down }
    Job.reset_column_information
    refute connection.column_exists?(:jobs, :market)

    {
      "Backfill Brazil" => [ "Brazil", nil ],
      "Backfill Portugal" => [ "Portugal", nil ],
      "Backfill Kenya" => [ "Kenya", "Remote" ],
      "Backfill Porto" => [ "Porto", "Remote" ],
      "Backfill Worldwide Brazil" => [ "Worldwide, Brazil", nil ],
      "Backfill Anywhere Brazil" => [ "Anywhere in Brazil", "Remote" ],
      "Backfill Blank" => [ nil, nil ]
    }.each_with_index do |(title, (location_text, remote_text)), index|
      insert_raw_job(connection, gupy_id:, title:, location_text:, remote_text:, index:)
    end

    ActiveRecord::Migration.suppress_messages { load_market_migration.new.up }
    Job.reset_column_information

    assert connection.column_exists?(:jobs, :market)
    assert connection.index_exists?(:jobs, :market)

    markets = connection.select_rows("SELECT title, market FROM jobs").to_h { |title, market| [ title, market.to_i ] }

    assert_equal 1, markets["Frontend Engineer Senior"]
    assert_equal 1, markets["Senior Ruby on Rails Developer"]
    assert_equal 1, markets["Backfill Brazil"]
    assert_equal 2, markets["Backfill Portugal"]
    assert_equal 0, markets["Backfill Kenya"]
    assert_equal 0, markets["Backfill Porto"]
    assert_equal 2, markets["Backfill Worldwide Brazil"]
    assert_equal 1, markets["Backfill Anywhere Brazil"]
    assert_equal 0, markets["Backfill Blank"]

    ActiveRecord::Migration.suppress_messages { load_market_migration.new.down }
    Job.reset_column_information
    refute connection.column_exists?(:jobs, :market)
  ensure
    restore_market_column
  end

  private
    def load_market_migration
      require Rails.root.join("db/migrate/20261104150000_add_market_to_jobs.rb").to_s
      AddMarketToJobs
    end

    def insert_raw_job(connection, gupy_id:, title:, location_text:, remote_text:, index:)
      now = connection.quote(Time.current)
      connection.execute(<<~SQL)
        INSERT INTO jobs (
          job_source_id, title, company_name, apply_url, canonical_url, source_url, fingerprint,
          location_text, remote_text, raw_payload, first_seen_at, last_seen_at, last_validated_at,
          created_at, updated_at
        ) VALUES (
          #{connection.quote(gupy_id)}, #{connection.quote(title)}, 'Backfill Co',
          #{connection.quote("https://backfill.example.com/jobs/#{index}")},
          #{connection.quote("https://backfill.example.com/jobs/#{index}")},
          #{connection.quote("https://backfill.example.com/jobs/#{index}")},
          #{connection.quote("backfill::#{index}")},
          #{connection.quote(location_text)}, #{connection.quote(remote_text)}, '{}'::jsonb,
          #{now}, #{now}, #{now}, #{now}, #{now}
        )
      SQL
    end

    def restore_market_column
      connection = ActiveRecord::Base.connection
      unless connection.column_exists?(:jobs, :market)
        ActiveRecord::Migration.suppress_messages { load_market_migration.new.up }
      end
    ensure
      connection&.schema_cache&.clear!
      Job.reset_column_information
    end
end
