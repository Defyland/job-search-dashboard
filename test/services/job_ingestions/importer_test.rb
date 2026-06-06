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
end
