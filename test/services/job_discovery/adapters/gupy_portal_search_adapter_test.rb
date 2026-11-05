require "test_helper"

class JobDiscovery::Adapters::GupyPortalSearchAdapterTest < ActiveSupport::TestCase
  API_URL = "https://portal.gupy.io/api/job-search/jobs".freeze

  # Answers each search request by its `jobName` and `offset`, and records every URL requested.
  class ScriptedFetcher
    attr_reader :urls

    def initialize(responses = {})
      @responses = responses
      @urls = []
    end

    def call(url, limit: 5)
      @urls << url
      query = URI.decode_www_form(URI.parse(url).query).to_h
      response = @responses.fetch([ query.fetch("jobName"), query.fetch("offset").to_i ]) do
        raise "unexpected request: #{url}"
      end

      raise response if response.is_a?(Exception)

      response
    end
  end

  class FakeRegistry
    def initialize(fetcher)
      @fetcher = fetcher
    end

    def supports?(_adapter_key)
      true
    end

    def fetch(_adapter_key)
      fetcher = @fetcher
      Class.new(JobDiscovery::Adapters::GupyPortalSearchAdapter) do
        define_method(:initialize) { |policy: nil| super(fetcher:, policy:) }
      end
    end
  end

  test "searches the stacks of the active profiles, three terms per scan, in profile order" do
    profiles = [ create_profile(stacks: %w[java react]), create_profile(stacks: %w[typescript ruby]) ]
    fetcher = ScriptedFetcher.new(empty_pages("java", "react", "typescript"))

    adapter(fetcher, profiles:).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[java react typescript], searched_terms(fetcher)
  end

  test "rotates the searched terms so each scan starts where the previous one stopped" do
    profiles = [ create_profile(stacks: %w[java react ruby rails]) ]
    source = create_source
    responses = empty_pages("java", "react", "ruby", "rails")
    first_fetcher = ScriptedFetcher.new(responses)
    second_fetcher = ScriptedFetcher.new(responses)

    adapter(first_fetcher, profiles:).scan(source_scan: build_source_scan(source:), window_days: 20)
    adapter(second_fetcher, profiles:).scan(source_scan: build_source_scan(source:), window_days: 20)

    assert_equal %w[java react ruby], searched_terms(first_fetcher)
    assert_equal %w[rails java react], searched_terms(second_fetcher)
  end

  test "records the terms left out of a scan and the terms whose pages ran out" do
    profiles = [ create_profile(stacks: %w[java react ruby rails]) ]
    responses = empty_pages("react", "ruby").merge(
      [ "java", 0 ] => page_body(jobs: full_page(first_id: 1)),
      [ "java", 100 ] => page_body(jobs: full_page(first_id: 101)),
      [ "java", 200 ] => page_body(jobs: full_page(first_id: 201))
    )
    source_scan = build_source_scan

    adapter(ScriptedFetcher.new(responses), profiles:).scan(source_scan:, window_days: 20)

    assert_equal(
      { "searched" => %w[java react ruby], "pending" => %w[rails], "truncated" => %w[java] },
      source_scan.reload.metadata.fetch("search_terms")
    )
  end

  test "pages each term by limit and offset and stops at the first short page" do
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(jobs: full_page(first_id: 1)),
      [ "ruby on rails", 100 ] => page_body(jobs: [ job(id: 101), job(id: 102) ])
    )

    candidates = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal [ 0, 100 ], offsets(fetcher)
    assert_equal 102, candidates.size
    assert_equal "102", candidates.last[:external_job_id]
  end

  test "ignores an inconsistent pagination.total and keeps paging full pages" do
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(jobs: full_page(first_id: 1), total: 0),
      [ "ruby on rails", 100 ] => page_body(jobs: [ job(id: 101) ], total: 0)
    )

    candidates = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal [ 0, 100 ], offsets(fetcher)
    assert_equal 101, candidates.size
  end

  test "requests at most three terms and three pages per term" do
    profiles = [ create_profile(stacks: %w[java react ruby rails]) ]
    responses = {}
    %w[java react ruby].each_with_index do |term, term_index|
      [ 0, 100, 200 ].each do |offset|
        responses[[ term, offset ]] = page_body(jobs: full_page(first_id: (term_index * 1_000) + offset + 1))
      end
    end
    fetcher = ScriptedFetcher.new(responses)

    adapter(fetcher, profiles:).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal 9, fetcher.urls.size
    assert_equal 3, fetcher.urls.count { |url| query_for(url)["jobName"] == "java" }
    assert_empty fetcher.urls.select { |url| query_for(url)["jobName"] == "rails" }
  end

  test "a 400 ends only the term that caused it and the next term still runs" do
    profiles = [ create_profile(stacks: [ "ruby on rails", "rails" ]) ]
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => request_error(400),
      [ "rails", 0 ] => page_body(jobs: [ job(id: 7) ])
    )

    candidates = adapter(fetcher, profiles:).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal 2, fetcher.urls.size
    assert_equal %w[7], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "other HTTP errors are not swallowed" do
    fetcher = ScriptedFetcher.new([ "ruby on rails", 0 ] => request_error(500))

    assert_raises(JobDiscovery::Fetcher::RequestError) do
      adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)
    end
  end

  test "maps the search payload to a candidate and never opens the listing" do
    published_at = 3.days.ago.change(usec: 0)
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(
        jobs: [
          job(
            id: 12_829_831,
            name: "Pessoa Desenvolvedora Ruby on Rails Sênior  ",
            host: "fcamara.gupy.io",
            published_at:,
            city: "Recife",
            state: "Pernambuco",
            description: "<p>Vaga remota em Ruby on Rails</p>",
            career_page_name: "VENHA SER"
          )
        ]
      )
    )

    candidate = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20).first

    assert_equal 1, fetcher.urls.size
    assert fetcher.urls.all? { |url| url.start_with?(API_URL) }, "only the search endpoint is requested"
    assert_equal "12829831", candidate[:external_job_id]
    assert_equal "Pessoa Desenvolvedora Ruby on Rails Sênior", candidate[:title]
    assert_equal "VENHA SER", candidate[:company_name]
    assert_equal "https://fcamara.gupy.io/jobs/12829831", candidate[:canonical_url]
    assert_equal "https://fcamara.gupy.io/jobs/12829831", candidate[:apply_url]
    assert_equal "https://fcamara.gupy.io/jobs/12829831", candidate[:source_url]
    assert_equal "Recife, Pernambuco", candidate[:location_text]
    assert_includes candidate[:remote_text], "remote"
    assert_equal "<p>Vaga remota em Ruby on Rails</p>", candidate[:description]
    assert_equal published_at, candidate[:published_at]
    assert_equal "gupy-portal", candidate[:source_slug]
    assert_equal "Gupy Portal", candidate[:source_name]
  end

  test "requests the search with the term, remote workplace type, limit and offset" do
    fetcher = ScriptedFetcher.new([ "ruby on rails", 0 ] => page_body(jobs: []))

    adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    query = query_for(fetcher.urls.first)
    assert_equal "ruby on rails", query["jobName"]
    assert_equal "remote", query["workplaceType"]
    assert_equal "100", query["limit"]
    assert_equal "0", query["offset"]
  end

  test "accepts senior java, react and ruby listings for the profiles that search them" do
    profiles = [ create_profile(stacks: %w[java]), create_profile(stacks: %w[react]), create_profile(stacks: %w[ruby]) ]
    fetcher = ScriptedFetcher.new(
      [ "java", 0 ] => page_body(jobs: [ job(id: 1, name: "Desenvolvedor(a) Java Sênior", description: "Vaga remota com Java e Spring") ]),
      [ "react", 0 ] => page_body(jobs: [ job(id: 2, name: "Desenvolvedor(a) React Sênior", description: "Vaga remota com React") ]),
      [ "ruby", 0 ] => page_body(jobs: [ job(id: 3, name: "Desenvolvedor(a) Ruby Sênior", description: "Vaga remota com Ruby") ])
    )

    candidates = adapter(fetcher, profiles:).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[java react ruby], searched_terms(fetcher)
    assert_equal %w[strong strong strong], candidates.map { |candidate| candidate[:classification] }
    assert_equal %w[1 2 3], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "drops listings whose host is not a valid gupy host or whose id is not numeric" do
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(
        jobs: [
          job(id: 1, host: "mesainc&59344&inactive.gupy.io"),
          job(id: 2, host: "portal.gupy.io"),
          job(id: 3, host: "evil.example.com"),
          job(id: "abc"),
          job(id: 5)
        ]
      )
    )

    candidates = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[5], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "drops listings published before the scan window" do
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(jobs: [ job(id: 1, published_at: 2.days.ago), job(id: 2, published_at: 40.days.ago) ])
    )

    candidates = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[1], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "leaves the title gate to the policy, so a non-senior title is dropped like in the other adapters" do
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(
        jobs: [ job(id: 1, name: "Pessoa Desenvolvedora Ruby on Rails - Pleno"), job(id: 2) ]
      )
    )

    candidates = adapter(fetcher, profiles: ruby_on_rails_profiles).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[2], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "keeps each job id once when it repeats across terms" do
    profiles = [ create_profile(stacks: [ "ruby on rails", "rails" ]) ]
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(jobs: [ job(id: 9) ]),
      [ "rails", 0 ] => page_body(jobs: [ job(id: 9), job(id: 10) ])
    )

    candidates = adapter(fetcher, profiles:).scan(source_scan: build_source_scan, window_days: 20)

    assert_equal %w[9 10], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "links a portal listing to the existing job from another source with the same canonical url" do
    # The fixture profiles are active too; deactivating them keeps the scan to the stack under test.
    SearchProfile.update_all(active: false)
    create_profile(stacks: [ "ruby on rails" ])
    other_source = JobSource.create!(
      name: "Other Source",
      slug: "other-source-dedup",
      host: "example.com",
      base_url: "https://example.com",
      source_kind: :ats,
      adapter_key: "gupy_company_boards",
      supports_backfill: true,
      scan_window_days: 20
    )
    existing = Job.create!(
      job_source: other_source,
      title: "Senior Ruby on Rails Engineer",
      company_name: "Clicksign",
      apply_url: "https://clicksign.gupy.io/jobs/11234166",
      canonical_url: "https://clicksign.gupy.io/jobs/11234166",
      source_url: "https://clicksign.gupy.io/jobs/11234166",
      fingerprint: "clicksign::senior ruby on rails engineer::clicksign.gupy.io::11234166",
      remote_text: "Remoto",
      location_text: "Brasil"
    )
    portal_source = JobSource.create!(
      name: "Gupy Portal Dedup",
      slug: "gupy-portal-dedup",
      host: "portal.gupy.io",
      base_url: "https://portal.gupy.io",
      source_kind: :ats,
      adapter_key: "gupy_portal_search",
      supports_backfill: true,
      scan_window_days: 20
    )
    fetcher = ScriptedFetcher.new(
      [ "ruby on rails", 0 ] => page_body(
        jobs: [ job(id: 11_234_166, host: "clicksign.gupy.io", name: "Senior Ruby on Rails Engineer", career_page_name: "VENHA SER") ]
      )
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: portal_source.id),
      registry: FakeRegistry.new(fetcher)
    ).call

    candidate = result.search_run.discovered_jobs.find_by!(external_job_id: "11234166")
    assert_equal existing.id, candidate.job_id, "the portal candidate must link to the existing job"
    assert_equal 1, Job.where(canonical_url: "https://clicksign.gupy.io/jobs/11234166").count, "no duplicate job may be created"
  end

  test "is registered in the adapter registry and the source catalog, with terms taken from the profiles" do
    assert JobDiscovery::Registry.supports?("gupy_portal_search")

    entry = JobSources::Catalog::DEFAULTS.find { |source| source[:slug] == "gupy-portal" }
    assert_equal "gupy_portal_search", entry[:adapter_key]
    assert_equal "https://portal.gupy.io", entry[:base_url]
    assert_equal "remote", entry.dig(:settings, :workplace_type)
    assert_nil entry.dig(:settings, :terms), "the search terms must come from the active profiles, not from the catalog"
  end

  private
    def adapter(fetcher, profiles:)
      JobDiscovery::Adapters::GupyPortalSearchAdapter.new(
        fetcher:,
        policy: JobDiscovery::Policy.new(search_profiles: profiles)
      )
    end

    def ruby_on_rails_profiles
      [ create_profile(stacks: [ "ruby on rails" ]) ]
    end

    def create_profile(stacks:)
      users(:one).search_profiles.create!(name: "Perfil #{stacks.join(' ')} #{SecureRandom.hex(3)}", target_stacks: stacks)
    end

    def create_source
      JobSource.create!(
        name: "Gupy Portal Test",
        slug: "gupy-portal-test-#{SecureRandom.hex(4)}",
        host: "portal.gupy.io",
        base_url: "https://portal.gupy.io",
        source_kind: :ats,
        adapter_key: "gupy_portal_search",
        supports_backfill: true,
        scan_window_days: 20
      )
    end

    def build_source_scan(source: create_source)
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def empty_pages(*terms)
      terms.to_h { |term| [ [ term, 0 ], page_body(jobs: []) ] }
    end

    def searched_terms(fetcher)
      fetcher.urls.map { |url| query_for(url)["jobName"] }.uniq
    end

    def query_for(url)
      URI.decode_www_form(URI.parse(url).query).to_h
    end

    def offsets(fetcher)
      fetcher.urls.map { |url| query_for(url)["offset"].to_i }
    end

    def request_error(code)
      JobDiscovery::Fetcher::RequestError.new("request failed: #{API_URL} -> #{code}", code:)
    end

    def page_body(jobs:, total: nil)
      {
        "data" => jobs,
        "pagination" => { "total" => total || jobs.size, "limit" => 100, "offset" => 0 }
      }.to_json
    end

    def full_page(first_id:)
      Array.new(100) { |index| job(id: first_id + index) }
    end

    def job(id:, name: "Desenvolvedor(a) Ruby on Rails Sênior", host: "fcamara.gupy.io", published_at: 2.days.ago, city: nil, state: nil, description: "Vaga remota em Ruby on Rails", career_page_name: "Fcamara")
      {
        "id" => id,
        "name" => name,
        "applicationDeadline" => "2027-01-02T00:00:00.000Z",
        "description" => description,
        "careerPageName" => career_page_name,
        "careerPageLogo" => nil,
        "careerPageUrl" => "",
        "type" => "vacancy_type_effective",
        "publishedDate" => published_at.iso8601,
        "workplaceType" => "remote",
        "city" => city,
        "state" => state,
        "jobUrl" => "https://#{host}/job/opaque-token?jobBoardSource=gupy_portal",
        "badges" => { "friendlyBadge" => true }
      }
    end
end
