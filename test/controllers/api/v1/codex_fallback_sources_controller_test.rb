require "test_helper"

class Api::V1::CodexFallbackSourcesControllerTest < ActionDispatch::IntegrationTest
  test "returns enabled codex fallback sources with policy guidance" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    previous_search_key = ENV["SEARCH_INDEX_API_KEY"]
    previous_serpapi_key = ENV["SERPAPI_API_KEY"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"
    ENV["SEARCH_INDEX_API_KEY"] = nil
    ENV["SERPAPI_API_KEY"] = nil
    JobSources::Catalog.seed!

    get api_v1_codex_fallback_sources_path,
        headers: { "Authorization" => "Bearer secret-token" },
        as: :json

    assert_response :success

    body = response.parsed_body
    slugs = body.fetch("sources").map { |source| source.fetch("slug") }

    assert_includes slugs, "apinfo"
    assert_includes slugs, "bamboohr"
    assert_includes slugs, "get-great-careers"
    assert_includes slugs, "icims"
    assert_includes slugs, "jazzhr"
    assert_includes slugs, "jobvite"
    assert_includes slugs, "landor-ats"
    assert_includes slugs, "linkedin"
    assert_includes slugs, "netvagas"
    assert_includes slugs, "remotely-works"
    assert_includes slugs, "rubyonremote"
    assert_includes slugs, "workday"
    assert_equal "/api/v1/job_ingestions", body.fetch("ingestion_endpoint")
    assert_equal false, body.dig("search_index", "rails_native_enabled")
    assert_includes body.dig("search_index", "queries").map { |query| query.fetch("query") }.join("\n"), "site:jobs.ashbyhq.com"
    default_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("Ruby/Rails") }
    inclusive_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("afirmativas") }

    assert_includes default_policy.fetch("stack_terms"), "ruby on rails"
    assert_includes default_policy.fetch("exclude_terms"), "mulheres"
    assert_equal "both", default_policy.fetch("language_scope")
    assert_not_includes inclusive_policy.fetch("exclude_terms"), "women only"
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
    ENV["SEARCH_INDEX_API_KEY"] = previous_search_key
    ENV["SERPAPI_API_KEY"] = previous_serpapi_key
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
