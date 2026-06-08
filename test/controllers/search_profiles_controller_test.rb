require "cgi"
require "test_helper"

class SearchProfilesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeIntentCompiler
    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      raise ArgumentError, "expected salesforce stack" unless technology_intent == "salesforce"
      raise ArgumentError, "unexpected seniority" unless seniority_preset == "senior"
      raise ArgumentError, "unexpected language" unless language_scope == "both"
      raise ArgumentError, "unexpected remote flag" unless required_remote == "1" || required_remote == true
      raise ArgumentError, "unexpected region" unless region_scope == "brazil_latam"
      raise ArgumentError, "unexpected women flag" unless include_women_only == "0" || include_women_only == false

      {
        "profile_name_suggestion" => "Senior Salesforce Remote BR/LatAm",
        "canonical_stacks" => [ "salesforce" ],
        "title_variants_pt" => [ "desenvolvedor salesforce", "consultor salesforce" ],
        "title_variants_en" => [ "salesforce developer", "salesforce engineer" ],
        "stack_aliases" => [
          { "canonical_stack" => "salesforce", "aliases" => [ "apex", "lightning", "sales cloud" ] }
        ],
        "model" => "claude-sonnet-4-20250514",
        "provider" => "anthropic"
      }
    end
  end

  class FixedSyncResult
    def initialize(result)
      @result = result
    end

    def call
      @result
    end
  end

  setup do
    sign_in_as(users(:one))
  end

  test "lists search profiles" do
    get search_profiles_path

    assert_response :success
    assert_match "Senior Ruby/Rails/React", response.body
  end

  test "compiles intent preview and saves an intent-backed profile" do
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Senior Salesforce Developer",
      company_name: "Acme",
      apply_url: "https://acme.gupy.io/jobs/salesforce-1",
      canonical_url: "https://acme.gupy.io/jobs/salesforce-1",
      source_url: "https://acme.gupy.io/jobs/salesforce-1",
      ats_name: "Gupy",
      external_job_id: "salesforce-1",
      remote_text: "Remoto Brasil",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada ha 1 dia",
      published_at: 1.day.ago,
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago,
      fingerprint: "acme::senior salesforce developer::gupy.io::salesforce-1",
      raw_payload: {
        title: "Senior Salesforce Developer",
        company: "Acme",
        description: "Apex, Lightning, Sales Cloud"
      }
    )

    with_fake_intent_compiler(FakeIntentCompiler.new) do
      post search_profiles_path, params: { search_profile: compiled_form_params, preview_compile: "1" }
    end

    assert_response :success
    assert_match "Preview gerado", response.body
    assert_match "salesforce developer", response.body

    compiled_payload = extract_compiled_payload(response.body)

    assert_difference("SearchProfile.count", 1) do
      assert_enqueued_with(
        job: DiscoverJobsRunJob,
        args: lambda { |args|
          options = args.first&.symbolize_keys
          options == {
            window_days: 20,
            trigger_source: :manual,
            search_profile_id: options[:search_profile_id]
          } && options[:search_profile_id].is_a?(Integer)
        }
      ) do
        post search_profiles_path, params: {
          search_profile: compiled_form_params.merge(
            compiled_profile_payload: compiled_payload
          )
        }
      end
    end

    profile = SearchProfile.order(:created_at).last
    assert_redirected_to jobs_path(search_profile_id: profile.id)
    assert_equal [ "salesforce" ], profile.target_stacks
    assert profile.intent_backed?
    assert_equal "brazil_latam", profile.intent_settings["region_scope"]
    assert_includes profile.compiler_stack_aliases["salesforce"], "apex"
    assert profile.job_matches.exists?
  end

  test "rejects saving with stale compiled payload when the simple intent changes" do
    with_fake_intent_compiler(FakeIntentCompiler.new) do
      post search_profiles_path, params: { search_profile: compiled_form_params, preview_compile: "1" }
    end

    compiled_payload = extract_compiled_payload(response.body)

    assert_no_difference("SearchProfile.count") do
      post search_profiles_path, params: {
        search_profile: compiled_form_params.merge(
          "technology_intent" => "servicenow",
          "compiled_profile_payload" => compiled_payload
        )
      }
    end

    assert_response :unprocessable_entity
    assert_match "Gere novamente antes de salvar", response.body
  end

  test "redirects with alert when the local cache bootstrap fails" do
    sync_result = SearchProfiles::Sync::Result.new(
      discovered_bootstrap_result: nil,
      external_run_enqueued: true,
      errors: [ "cache import failed" ]
    )

    with_fake_sync(FixedSyncResult.new(sync_result)) do
      post search_profiles_path, params: {
        search_profile: {
          name: "Senior Java Remote",
          active: "1",
          required_remote: "1",
          include_women_only: "0",
          language_scope: "both",
          technology_intent: "",
          seniority_preset: "senior",
          region_scope: "brazil_latam",
          target_stacks_text: "java",
          target_titles_text: "developer, engineer",
          seniority_terms_text: "senior, sênior, sr",
          location_terms_text: "remote, remoto, brasil, brazil",
          negative_terms_text: SearchProfile::DEFAULT_NEGATIVE_TERMS.join(", ")
        }
      }
    end

    follow_redirect!
    assert_match "A busca externa foi iniciada, mas o reaproveitamento local falhou: cache import failed.", response.body
  end

  test "updates women only preference manually while preserving profile settings" do
    profile = users(:one).search_profiles.create!(
      SearchProfiles::ProfileBuilder.from_compiled(
        simple_input: {
          "name" => "Senior Java Remote",
          "technology_intent" => "java",
          "seniority_preset" => "senior",
          "language_scope" => "both",
          "required_remote" => true,
          "region_scope" => "brazil_latam",
          "include_women_only" => false
        },
        compiled_payload: {
          "profile_name_suggestion" => "Senior Java Remote",
          "canonical_stacks" => [ "java" ],
          "title_variants_pt" => [ "desenvolvedor java" ],
          "title_variants_en" => [ "java developer" ],
          "stack_aliases" => [ { "canonical_stack" => "java", "aliases" => [ "spring boot" ] } ],
          "model" => "claude-sonnet-4-20250514",
          "request_fingerprint" => "fingerprint"
        }
      )
    )

    assert_enqueued_with(
      job: DiscoverJobsRunJob,
      args: ->(args) { args == [ { window_days: 20, trigger_source: :manual, search_profile_id: profile.id } ] }
    ) do
      patch search_profile_path(profile), params: {
        search_profile: {
          name: profile.name,
          required_remote: "1",
          include_women_only: "1",
          language_scope: "both",
          technology_intent: "java",
          seniority_preset: "senior",
          region_scope: "brazil_latam",
          target_stacks_text: profile.target_stacks_text,
          target_titles_text: profile.target_titles_text,
          seniority_terms_text: profile.seniority_terms_text,
          location_terms_text: profile.location_terms_text,
          negative_terms_text: profile.negative_terms_text
        }
      }
    end

    assert_redirected_to search_profiles_path
    assert profile.reload.include_women_only?
    assert profile.intent_backed?
    assert_includes profile.compiler_stack_aliases["java"], "spring boot"
  end

  test "updates manual profile and refreshes stored matches" do
    ruby_job = Job.create!(
      job_source: job_sources(:workable),
      title: "Senior Ruby Engineer",
      company_name: "Legacy",
      apply_url: "https://jobs.workable.com/view/ruby-controller-2",
      canonical_url: "https://jobs.workable.com/view/ruby-controller-2",
      source_url: "https://jobs.workable.com/view/ruby-controller-2",
      ats_name: "Workable",
      external_job_id: "ruby-controller-2",
      remote_text: "Remote Brazil",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada ha 2 dias",
      published_at: 2.days.ago,
      first_seen_at: 2.days.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago,
      fingerprint: "legacy::senior ruby engineer::jobs.workable.com::ruby-controller-2",
      raw_payload: {
        title: "Senior Ruby Engineer",
        company: "Legacy",
        description: "Ruby, Rails, remote Brazil"
      }
    )
    java_job = Job.create!(
      job_source: job_sources(:gupy),
      title: "Senior Java Engineer",
      company_name: "Nova",
      apply_url: "https://nova.gupy.io/jobs/java-controller-2",
      canonical_url: "https://nova.gupy.io/jobs/java-controller-2",
      source_url: "https://nova.gupy.io/jobs/java-controller-2",
      ats_name: "Gupy",
      external_job_id: "java-controller-2",
      remote_text: "Remoto Brasil",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada ha 1 dia",
      published_at: 1.day.ago,
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago,
      fingerprint: "nova::senior java engineer::gupy.io::java-controller-2",
      raw_payload: {
        title: "Senior Java Engineer",
        company: "Nova",
        description: "Java, Spring Boot, remote Brazil"
      }
    )

    profile = users(:one).search_profiles.create!(
      name: "Senior Ruby Remote",
      slug: "senior-ruby-remote-refresh",
      active: true,
      required_remote: true,
      include_women_only: false,
      language_scope: :both,
      target_stacks: [ "ruby" ],
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior", "sênior", "sr" ],
      location_terms: [ "remote", "remoto", "brasil", "brazil" ],
      negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
      scan_window_days: 20
    )

    SearchProfiles::Bootstrapper.new(search_profile: profile, job_scope: Job.where(id: [ ruby_job.id, java_job.id ]).includes(:job_source)).call
    assert_equal [ ruby_job.id ], JobMatch.for_profile(profile).pluck(:job_id)

    assert_enqueued_with(
      job: DiscoverJobsRunJob,
      args: ->(args) { args == [ { window_days: 20, trigger_source: :manual, search_profile_id: profile.id } ] }
    ) do
      patch search_profile_path(profile), params: {
        search_profile: {
          name: "Senior Java Remote",
          active: "1",
          required_remote: "1",
          include_women_only: "0",
          language_scope: "both",
          technology_intent: "",
          seniority_preset: "senior",
          region_scope: "brazil_latam",
          target_stacks_text: "java",
          target_titles_text: "developer, engineer",
          seniority_terms_text: "senior, sênior, sr",
          location_terms_text: "remote, remoto, brasil, brazil",
          negative_terms_text: SearchProfile::DEFAULT_NEGATIVE_TERMS.join(", ")
        }
      }
    end

    assert_redirected_to search_profiles_path
    refute_includes JobMatch.for_profile(profile).pluck(:job_id), ruby_job.id
    assert_includes JobMatch.for_profile(profile).pluck(:job_id), java_job.id
  end

  private
    def compiled_form_params
      {
        name: "Senior Salesforce Remote BR/LatAm",
        technology_intent: "salesforce",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: "1",
        region_scope: "brazil_latam",
        include_women_only: "0"
      }
    end

    def extract_compiled_payload(body)
      escaped = body[/name="search_profile\[compiled_profile_payload\]".*?value="([^"]+)"/m, 1]
      CGI.unescapeHTML(escaped.to_s)
    end

    def with_fake_intent_compiler(fake_compiler)
      original_new = SearchProfiles::IntentCompiler.method(:new)
      SearchProfiles::IntentCompiler.singleton_class.send(:define_method, :new) { |_args = nil, **_kwargs| fake_compiler }
      yield
    ensure
      SearchProfiles::IntentCompiler.singleton_class.send(:define_method, :new) do |*args, **kwargs|
        original_new.call(*args, **kwargs)
      end
    end

    def with_fake_sync(fake_sync)
      original_new = SearchProfiles::Sync.method(:new)
      SearchProfiles::Sync.singleton_class.send(:define_method, :new) { |_args = nil, **_kwargs| fake_sync }
      yield
    ensure
      SearchProfiles::Sync.singleton_class.send(:define_method, :new) do |*args, **kwargs|
        original_new.call(*args, **kwargs)
      end
    end
end
