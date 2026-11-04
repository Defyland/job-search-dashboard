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

  test "replays a retried request with the same client_run_id" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      body = ingestion_body(run_extra: { client_run_id: "ctrl-replay-1" })

      post api_v1_job_ingestions_path, params: body, headers: auth_headers, as: :json
      assert_response :created
      first_id = response.parsed_body.fetch("search_run_id")
      assert_equal false, response.parsed_body.fetch("replayed")

      assert_no_difference([ "SearchRun.count", "Job.count", "JobMatch.count", "SearchRunItem.count" ]) do
        post api_v1_job_ingestions_path, params: body, headers: auth_headers, as: :json
      end

      assert_response :ok
      assert_equal first_id, response.parsed_body.fetch("search_run_id")
      assert_equal true, response.parsed_body.fetch("replayed")
      assert_equal 1, response.parsed_body.dig("summary", "imported_count")
    end
  end

  test "returns 409 when a client_run_id is reused with a different payload" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      post api_v1_job_ingestions_path,
           params: ingestion_body(run_extra: { client_run_id: "ctrl-conflict-1" }),
           headers: auth_headers,
           as: :json
      assert_response :created

      assert_no_difference([ "SearchRun.count", "Job.count" ]) do
        post api_v1_job_ingestions_path,
             params: ingestion_body(run_extra: { client_run_id: "ctrl-conflict-1" }, title: "Staff React Native Developer"),
             headers: auth_headers,
             as: :json
      end

      assert_response :conflict
      assert_equal "client_run_id_conflict", response.parsed_body.fetch("error")
      assert_includes response.parsed_body.fetch("details").join, "already used with a different payload"
    end
  end

  test "creates a run on every request without a client_run_id" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      assert_difference("SearchRun.count", 2) do
        2.times do
          post api_v1_job_ingestions_path, params: ingestion_body, headers: auth_headers, as: :json
          assert_response :created
          assert_equal false, response.parsed_body.fetch("replayed")
        end
      end
    end
  end

  test "treats a blank client_run_id as no key" do
    with_env("INGEST_SHARED_TOKEN" => "secret-token") do
      assert_difference("SearchRun.count", 2) do
        2.times do
          post api_v1_job_ingestions_path,
               params: ingestion_body(run_extra: { client_run_id: "" }),
               headers: auth_headers,
               as: :json
          assert_response :created
        end
      end
    end
  end

  private
    def auth_headers(token = "secret-token")
      { "Authorization" => "Bearer #{token}" }
    end

    def ingestion_body(run_extra: {}, title: "Senior React Native Developer")
      {
        run: { window_label: "24h", trigger_source: "codex_automation" }.merge(run_extra),
        jobs: [
          {
            title:,
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
      }
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
