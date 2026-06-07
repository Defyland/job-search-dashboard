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
    assert_equal "Example", Job.order(:created_at).last.company_name
    assert_equal "14d", result.search_run.window_label
  end

  test "updates an existing job without resetting user state" do
    jobs(:ruby_role).update!(user_state: :applied)

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
    assert_equal "applied", jobs(:ruby_role).reload.user_state
    assert_equal 96, jobs(:ruby_role).score
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
    JobSource.seed_defaults!
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
    JobSource.seed_defaults!
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
    JobSource.seed_defaults!
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
end
