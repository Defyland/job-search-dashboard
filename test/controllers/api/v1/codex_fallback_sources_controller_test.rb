require "test_helper"

class Api::V1::CodexFallbackSourcesControllerTest < ActionDispatch::IntegrationTest
  test "returns enabled codex fallback sources with policy guidance" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"
    JobSource.seed_defaults!

    get api_v1_codex_fallback_sources_path,
        headers: { "Authorization" => "Bearer secret-token" },
        as: :json

    assert_response :success

    body = response.parsed_body
    slugs = body.fetch("sources").map { |source| source.fetch("slug") }

    assert_includes slugs, "apinfo"
    assert_includes slugs, "rubyonremote"
    assert_equal "/api/v1/job_ingestions", body.fetch("ingestion_endpoint")
    default_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("Ruby/Rails") }
    inclusive_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("afirmativas") }

    assert_includes default_policy.fetch("stack_terms"), "ruby on rails"
    assert_includes default_policy.fetch("exclude_terms"), "mulheres"
    assert_not_includes inclusive_policy.fetch("exclude_terms"), "women only"
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
  end

  test "rejects requests without ingestion token" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"

    get api_v1_codex_fallback_sources_path, as: :json

    assert_response :unauthorized
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
  end
end
