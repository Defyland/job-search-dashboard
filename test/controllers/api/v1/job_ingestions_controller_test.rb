require "test_helper"

class Api::V1::JobIngestionsControllerTest < ActionDispatch::IntegrationTest
  test "creates a run and imports jobs with a valid token" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"

    assert_difference([ "SearchRun.count", "Job.count" ], 1) do
      post api_v1_job_ingestions_path,
           params: {
             run: { window_label: "24h", trigger_source: "codex_automation" },
             jobs: [
               {
                 title: "Senior React Native Developer",
                 company: "CI&T",
                 apply_url: "https://jobs.lever.co/ciandt/ff314e5d-e080-43cf-bb51-a581c2701199",
                 canonical_url: "https://jobs.lever.co/ciandt/ff314e5d-e080-43cf-bb51-a581c2701199",
                 source_name: "Lever",
                 source_kind: "ats",
                 reason: "Titulo senior com React Native e remoto BR.",
                 stack_tags: [ "react native" ],
                 match_strength: "strong",
                 score: 91
               }
             ]
           },
           headers: { "Authorization" => "Bearer secret-token" },
           as: :json
    end

    assert_response :created
    assert_equal("CI&T", Job.order(:created_at).last.company_name)
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
  end
end
