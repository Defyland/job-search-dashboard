require "test_helper"

class JobIngestions::ImporterTest < ActiveSupport::TestCase
  test "imports a new job and creates a search run" do
    payload = {
      run: { window_label: "14d", trigger_source: "manual" },
      jobs: [
        {
          title: "Senior Ruby Engineer",
          company: "Example",
          apply_url: "https://jobs.example.com/ruby",
          canonical_url: "https://jobs.example.com/ruby",
          source_name: "Example Careers",
          source_kind: "company",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          reason: "Titulo senior com ruby no titulo.",
          stack_tags: [ "ruby" ],
          match_strength: "strong"
        }
      ]
    }

    result = JobIngestions::Importer.new(payload:).call

    assert result.success?
    job = Job.order(:created_at).last

    assert_equal "Example", job.company_name
    assert_equal [ search_profiles(:default) ], job.job_matches.map(&:search_profile)
    assert_equal "14d", result.search_run.window_label
  end

  test "imports contract type from payload" do
    payload = {
      run: { window_label: "14d", trigger_source: "manual" },
      jobs: [
        {
          title: "Senior React Engineer",
          company: "Contract Co",
          apply_url: "https://jobs.example.com/react",
          canonical_url: "https://jobs.example.com/react",
          source_name: "Example Careers",
          source_kind: "company",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          reason: "Titulo senior com react no titulo.",
          stack_tags: [ "react" ],
          match_strength: "strong",
          employment_type: "contractor"
        }
      ]
    }

    result = JobIngestions::Importer.new(payload:).call

    assert result.success?
    assert_predicate Job.order(:created_at).last, :contract_type_pj?
  end

  test "updates an existing job without resetting profile user state" do
    job_matches(:ruby_default).update!(user_state: :applied)

    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation" },
      jobs: [
        {
          title: jobs(:ruby_role).title,
          company: jobs(:ruby_role).company_name,
          apply_url: jobs(:ruby_role).apply_url,
          canonical_url: jobs(:ruby_role).canonical_url,
          source_name: jobs(:ruby_role).ats_name,
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          reason: "Atualizacao de validacao.",
          stack_tags: [ "ruby", "ruby on rails" ],
          score: 96
        }
      ]
    }

    result = JobIngestions::Importer.new(payload:).call

    assert result.success?
    assert_equal "applied", job_matches(:ruby_default).reload.user_state
    assert_equal 96, job_matches(:ruby_default).reload.score
  end

  test "recovers when a concurrent insert wins the job unique index race" do
    source = job_sources(:gupy)
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "24h", started_at: Time.current)
    store = JobIngestions::Store.new(search_run:)
    existing_job = Job.create!(
      title: "Senior Ruby Race",
      company_name: "Race Co",
      apply_url: "https://race.example/jobs/ruby/apply",
      canonical_url: "https://race.example/jobs/ruby",
      fingerprint: "race::senior ruby race::race.example::1",
      job_source: source,
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago
    )
    attributes = {
      title: "Senior Ruby Race",
      company_name: "Race Co",
      apply_url: "https://race.example/jobs/ruby/apply",
      canonical_url: "https://race.example/jobs/ruby",
      source_url: "https://race.example/jobs/ruby",
      ats_name: "Race",
      external_job_id: "1",
      remote_text: "Remote Brazil",
      location_text: "Brazil",
      seniority: "senior",
      match_strength: JobMatch.match_strengths.fetch("strong"),
      reason: "registro recuperado depois de corrida",
      score: 95,
      fingerprint: "race::senior ruby race::race.example::1",
      stack_tags: [ "ruby" ],
      source_host: "race.example",
      user_state: :new_match
    }
    payload = {
      "title" => attributes.fetch(:title),
      "company" => attributes.fetch(:company_name),
      "apply_url" => attributes.fetch(:apply_url),
      "canonical_url" => attributes.fetch(:canonical_url)
    }

    assert_no_difference("Job.count") do
      assert_difference("SearchRunItem.count", 1) do
        job = store.persist_job(existing_job: nil, source:, attributes:, payload:)

        assert_equal existing_job, job
      end
    end

    assert_equal "https://race.example/jobs/ruby/apply", existing_job.reload.apply_url
    assert_equal "updated", search_run.search_run_items.last.outcome
  end

  test "recovers when a concurrent insert wins the source uniqueness validation race" do
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "24h", started_at: Time.current)
    store = JobIngestions::Store.new(search_run:)
    existing_source = JobSource.create!(
      name: "Race Careers",
      slug: "race-careers",
      host: "race.example",
      base_url: "https://race.example",
      source_kind: :company,
      adapter_key: "manual_only",
      supports_backfill: false,
      scan_window_days: 20
    )
    attributes = {
      source_host: "race.example",
      source_url: "https://race.example/jobs/ruby",
      canonical_url: "https://race.example/jobs/ruby",
      ats_name: "Race Careers"
    }
    payload = {
      "source_name" => "Race Careers",
      "source_slug" => "race-careers",
      "source_kind" => "company"
    }
    duplicate = JobSource.new(slug: "race-careers")
    duplicate.errors.add(:slug, :taken)
    store.define_singleton_method(:persist_source) do |_source, _attributes, _payload, _source_name|
      raise ActiveRecord::RecordInvalid.new(duplicate)
    end

    assert_equal existing_source, store.resolve_source(attributes:, payload:)
  end

  test "recovers when a concurrent insert wins the job match uniqueness validation race" do
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "24h", started_at: Time.current)
    store = JobIngestions::Store.new(search_run:)
    job = Job.create!(
      title: "Senior Ruby Match Race",
      company_name: "Race Co",
      apply_url: "https://race.example/jobs/ruby-match/apply",
      canonical_url: "https://race.example/jobs/ruby-match",
      fingerprint: "race::senior ruby match::race.example::1",
      job_source: job_sources(:gupy),
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago
    )
    job.job_matches.load
    existing_match = JobMatch.create!(
      job:,
      search_profile: search_profiles(:default),
      match_strength: :strong,
      score: 70,
      reason: "registro criado por outra ingestao",
      seniority: "senior",
      stack_tags: [ "ruby" ],
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago
    )
    decision = JobDiscovery::Policy::Result.new(
      classification: :strong,
      reason: "match recuperado depois de corrida",
      stack_tags: [ "ruby" ],
      score: 96,
      seniority: "senior",
      remote_signal: "Remote Brazil",
      exclusion_reason: nil,
      search_profile: search_profiles(:default),
      eligibility_flags: []
    )

    assert_no_difference("JobMatch.count") do
      store.send(:persist_job_matches, job:, decisions: [ decision ])
    end

    assert_equal 96, existing_match.reload.score
    assert_equal "match recuperado depois de corrida", existing_match.reason
  end

  test "imports women only jobs only for profiles that allow them" do
    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation" },
      jobs: [
        {
          title: "Frontend Engineer Senior React",
          company: "Inclusive Co",
          apply_url: "https://inclusive.example/jobs/react",
          canonical_url: "https://inclusive.example/jobs/react",
          source_name: "Inclusive Careers",
          source_kind: "company",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          description: "Vaga afirmativa para mulheres na engenharia.",
          reason: "Titulo senior com React.",
          stack_tags: [ "react" ],
          match_strength: "strong"
        }
      ]
    }

    assert_difference([ "Job.count", "JobMatch.count" ], 1) do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
    end

    job = Job.order(:created_at).last
    assert_equal [ search_profiles(:women_inclusive) ], job.job_matches.map(&:search_profile)
    assert_includes job.job_matches.last.eligibility_flags, "women_only"
  end

  test "imports configurable senior salesforce profile matches" do
    profile = users(:one).search_profiles.create!(
      name: "Senior Salesforce Remote",
      target_stacks_text: "salesforce",
      target_titles_text: "software engineer, developer, consultant, salesforce",
      seniority_terms_text: "senior, sênior, sr",
      location_terms_text: "remote, remoto, brasil",
      negative_terms_text: "junior, pleno, internship",
      required_remote: true,
      include_women_only: false,
      language_scope: :english,
      scan_window_days: 20,
      active: true
    )

    payload = {
      run: { window_label: "24h", trigger_source: "manual" },
      jobs: [
        {
          title: "Senior Salesforce Developer",
          company: "Salesforce Test Co",
          apply_url: "https://salesforce-smoke.invalid/jobs/senior-salesforce-developer",
          canonical_url: "https://salesforce-smoke.invalid/jobs/senior-salesforce-developer",
          source_name: "Salesforce Smoke Careers",
          source_slug: "salesforce-smoke-careers",
          source_kind: "company",
          remote_signal: "Remote Brazil",
          location: "Brazil",
          description: "Salesforce Apex Lightning integrations",
          reason: "Salesforce senior remote smoke",
          match_strength: "strong"
        }
      ]
    }

    assert_difference([ "Job.count", "JobMatch.count" ], 1) do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
      assert_equal 1, result.summary[:imported_count]
      assert_equal 0, result.summary[:rejected_count]
    end

    job = Job.find_by!(canonical_url: "https://salesforce-smoke.invalid/jobs/senior-salesforce-developer")
    match = job.job_matches.find_by!(search_profile: profile)

    assert_equal "strong", match.match_strength
    assert_equal "new_match", match.user_state
    assert_equal [ "salesforce" ], match.stack_tags
  end

  test "imports configurable portuguese senior salesforce profile matches" do
    profile = users(:one).search_profiles.create!(
      name: "Senior Salesforce Remoto PT",
      target_stacks_text: "salesforce",
      target_titles_text: "salesforce, desenvolvedor, engenheiro, consultor",
      seniority_terms_text: "senior, sênior, sr",
      location_terms_text: "remote, remoto, brasil",
      negative_terms_text: "junior, pleno, internship",
      required_remote: true,
      include_women_only: false,
      language_scope: :portuguese,
      scan_window_days: 20,
      active: true
    )

    payload = {
      run: { window_label: "24h", trigger_source: "manual" },
      jobs: [
        {
          title: "Desenvolvedor Salesforce Sênior",
          company: "Salesforce Teste BR",
          apply_url: "https://salesforce-smoke.invalid/jobs/desenvolvedor-salesforce-senior",
          canonical_url: "https://salesforce-smoke.invalid/jobs/desenvolvedor-salesforce-senior",
          source_name: "Salesforce Smoke Careers",
          source_slug: "salesforce-smoke-careers",
          source_kind: "company",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          description: "Salesforce Apex Lightning integrations",
          reason: "Salesforce senior remoto smoke",
          match_strength: "strong"
        }
      ]
    }

    assert_difference([ "Job.count", "JobMatch.count" ], 1) do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
      assert_equal 1, result.summary[:imported_count]
      assert_equal 0, result.summary[:rejected_count]
    end

    job = Job.find_by!(canonical_url: "https://salesforce-smoke.invalid/jobs/desenvolvedor-salesforce-senior")
    match = job.job_matches.find_by!(search_profile: profile)

    assert_equal "strong", match.match_strength
    assert_equal [ "salesforce" ], match.stack_tags
  end

  test "reuses a catalog source instead of duplicating ats names" do
    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation" },
      jobs: [
        {
          title: "Senior Backend Engineer",
          company: "Clicksign",
          apply_url: "https://clicksign.gupy.io/jobs/11233965",
          canonical_url: "https://clicksign.gupy.io/jobs/11233965",
          source_url: "https://clicksign.gupy.io/jobs/11233965?jobBoardSource=gupy_public_page",
          source_name: "Gupy",
          source_kind: "ats",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          description: "Atuacao backend com Ruby e Rails em produto de assinatura digital.",
          reason: "Titulo senior com Ruby e Gupy.",
          stack_tags: [ "ruby" ],
          match_strength: "strong"
        }
      ]
    }

    assert_no_difference("JobSource.count") do
      result = JobIngestions::Importer.new(payload:).call
      assert result.success?
    end

    assert_equal job_sources(:gupy), Job.order(:created_at).last.job_source
  end

  test "records codex fallback timestamp on fallback source ingestion" do
    JobSources::Catalog.seed!
    source = JobSource.find_by!(slug: "rubyonremote")
    source.update!(last_codex_checked_at: nil, last_codex_fallback_at: nil)

    payload = {
      run: { window_label: "20d", trigger_source: "codex_automation", source_slugs: [ "rubyonremote" ] },
      jobs: [
        {
          title: "Senior Ruby on Rails Engineer",
          company: "Remote Ruby Co",
          apply_url: "https://rubyonremote.com/jobs/senior-ruby-on-rails-engineer",
          canonical_url: "https://rubyonremote.com/jobs/senior-ruby-on-rails-engineer",
          source_name: "RubyOnRemote",
          source_slug: "rubyonremote",
          source_kind: "platform",
          remote_signal: "Remote LatAm",
          location: "LatAm",
          reason: "Fonte bloqueada para Rails, validada via Codex fallback.",
          stack_tags: [ "ruby", "ruby on rails" ],
          match_strength: "strong"
        }
      ]
    }

    result = JobIngestions::Importer.new(payload:).call

    assert result.success?
    assert source.reload.last_codex_checked_at.present?
    assert source.reload.last_codex_fallback_at.present?
  end

  test "rejects codex jobs that do not pass backend policy" do
    search_profiles(:women_inclusive).update!(active: false)

    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation" },
      jobs: [
        {
          title: "Senior React Engineer",
          company: "Restricted Co",
          apply_url: "https://restricted.example/jobs/react",
          canonical_url: "https://restricted.example/jobs/react",
          source_name: "Restricted Careers",
          source_kind: "company",
          remote_signal: "Remoto Brasil",
          location: "Brasil",
          reason: "Women only role for React engineers",
          stack_tags: [ "react" ],
          match_strength: "strong"
        }
      ]
    }

    assert_no_difference("Job.count") do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
      assert_equal 0, result.summary[:imported_count]
      assert_equal 1, result.summary[:rejected_count]
      assert_equal "vaga afirmativa para mulheres", result.search_run.search_run_items.last.reason
    end
  end

  test "does not trust codex stack tags as positive match evidence" do
    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation" },
      jobs: [
        {
          title: "Senior Backend Engineer",
          company: "Generic Backend Co",
          apply_url: "https://generic-backend.example/jobs/senior-backend",
          canonical_url: "https://generic-backend.example/jobs/senior-backend",
          source_name: "Generic Careers",
          source_kind: "company",
          remote_signal: "Remote LatAm",
          location: "LatAm",
          description: "Backend services with Java and Python.",
          reason: "Codex inferred React from another page.",
          stack_tags: [ "react" ],
          match_strength: "strong"
        }
      ]
    }

    assert_no_difference("Job.count") do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
      assert_equal 0, result.summary[:imported_count]
      assert_equal 1, result.summary[:rejected_count]
      assert_equal "sem stack alvo no titulo ou contexto imediato", result.search_run.search_run_items.last.reason
    end
  end

  test "marks codex fallback sources checked even when there are no accepted jobs" do
    JobSources::Catalog.seed!
    source = JobSource.find_by!(slug: "apinfo")
    source.update!(last_codex_checked_at: nil, last_codex_fallback_at: nil)

    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation", source_slugs: [ "apinfo" ] },
      jobs: [],
      rejections: [
        {
          title: "Senior React Engineer",
          company: "APInfo Company",
          source_slug: "apinfo",
          reason: "vaga expirada"
        }
      ]
    }

    result = JobIngestions::Importer.new(payload:).call

    assert result.success?
    assert source.reload.last_codex_checked_at.present?
    assert_nil source.reload.last_codex_fallback_at
  end

  test "does not mark codex fallback accepted when fallback job is rejected by policy" do
    search_profiles(:women_inclusive).update!(active: false)
    JobSources::Catalog.seed!
    source = JobSource.find_by!(slug: "rubyonremote")
    source.update!(last_codex_checked_at: nil, last_codex_fallback_at: nil)

    payload = {
      run: { window_label: "24h", trigger_source: "codex_automation", source_slugs: [ "rubyonremote" ] },
      jobs: [
        {
          title: "Senior React Engineer",
          company: "Restricted Remote",
          apply_url: "https://rubyonremote.com/jobs/restricted-react",
          canonical_url: "https://rubyonremote.com/jobs/restricted-react",
          source_name: "RubyOnRemote",
          source_slug: "rubyonremote",
          source_kind: "platform",
          remote_signal: "Remote LatAm",
          location: "LatAm",
          reason: "Women only role for React engineers",
          stack_tags: [ "react" ],
          match_strength: "strong"
        }
      ]
    }

    assert_no_difference("Job.count") do
      result = JobIngestions::Importer.new(payload:).call

      assert result.success?
      assert_equal 1, result.summary[:rejected_count]
    end

    assert source.reload.last_codex_checked_at.present?
    assert_nil source.reload.last_codex_fallback_at
  end

  test "limits imported matches to the provided profile scope" do
    profile = users(:one).search_profiles.create!(
      name: "Senior Java Scoped",
      slug: "senior-java-scoped-importer",
      active: true,
      required_remote: true,
      include_women_only: false,
      language_scope: :both,
      target_stacks: [ "java" ],
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior", "sênior", "sr" ],
      location_terms: [ "remote", "remoto", "brasil", "brazil" ],
      negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
      scan_window_days: 20
    )

    payload = {
      run: { window_label: "24h", trigger_source: "manual", search_profile_id: profile.id },
      jobs: [
        {
          title: "Senior Java Developer",
          company: "Scoped Import Co",
          apply_url: "https://scoped-import.invalid/jobs/senior-java-developer",
          canonical_url: "https://scoped-import.invalid/jobs/senior-java-developer",
          source_name: "Scoped Import Careers",
          source_slug: "scoped-import-careers",
          source_kind: "company",
          remote_signal: "Remote Brazil",
          location: "Brazil",
          description: "Java Spring Boot role",
          reason: "Scoped Java role",
          match_strength: "strong"
        }
      ]
    }

    assert_difference([ "Job.count", "JobMatch.count" ], 1) do
      result = JobIngestions::Importer.new(payload:, profiles: [ profile ]).call

      assert result.success?
    end

    job = Job.find_by!(canonical_url: "https://scoped-import.invalid/jobs/senior-java-developer")
    assert_equal [ profile ], job.job_matches.map(&:search_profile)
  end
end
