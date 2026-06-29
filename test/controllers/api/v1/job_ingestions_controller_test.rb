require "test_helper"

class Api::V1::JobIngestionsControllerTest < ActionDispatch::IntegrationTest
  test "creates a run and imports jobs with a valid token" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      assert_difference([ "SearchRun.count", "Job.count" ], 1) do
        assert_difference("JobMatch.count", 2) do
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
                     remote_signal: "Remote Brazil",
                     location: "Brazil",
                     reason: "Titulo senior com React Native e remoto BR.",
                     stack_tags: [ "react native" ],
                     match_strength: "strong",
                     score: 91
                   }
                 ]
               },
               headers: auth_headers,
               as: :json
        end
      end

      assert_response :created
      job = Job.order(:created_at).last
      assert_equal("CI&T", job.company_name)
      assert_includes job.job_matches.map(&:search_profile), search_profiles(:default)
    end
  end

  test "rejects requests without a valid bearer token" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      assert_no_difference("SearchRun.count") do
        post api_v1_job_ingestions_path, params: { jobs: [] }, as: :json
      end

      assert_response :unauthorized
      assert_equal "invalid_ingest_token", response.parsed_body.fetch("error")
    end
  end

  test "returns validation details for malformed ingestion payloads" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      assert_no_difference("SearchRun.count") do
        post api_v1_job_ingestions_path,
             params: {
               run: { trigger_source: "codex_automation" },
               jobs: [ "not-a-job-object" ]
             },
             headers: auth_headers,
             as: :json
      end

      assert_response :unprocessable_entity
      assert_equal "invalid_ingestion_payload", response.parsed_body.fetch("error")
      assert_includes response.parsed_body.fetch("details"), "jobs must contain objects"
    end
  end

  private
    def auth_headers(token = "secret-token")
      { "Authorization" => "Bearer #{token}" }
    end

    def with_env(pairs)
      previous_values = pairs.keys.to_h { |key| [ key, ENV[key] ] }

      pairs.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end

      yield
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
end
