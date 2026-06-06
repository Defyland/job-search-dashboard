require "test_helper"

class JobDiscovery::Adapters::TeamtailorCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers board urls from persisted teamtailor jobs and scans paginated listings" do
    source = JobSource.create!(
      name: "Teamtailor Test",
      slug: "teamtailor-test",
      host: "teamtailor.com",
      base_url: "https://career.teamtailor.com",
      source_kind: :ats,
      adapter_key: "teamtailor_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 2 }
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Teamtailor Job",
      company_name: "Example Co",
      apply_url: "https://career.teamtailor.com/jobs/7010130-senior-react-engineer",
      canonical_url: "https://career.teamtailor.com/jobs/7010130-senior-react-engineer",
      source_url: "https://career.teamtailor.com/jobs/7010130-senior-react-engineer",
      fingerprint: "seed::teamtailor::7010130",
      reason: "seed",
      score: 88,
      match_strength: :strong,
      seniority: "senior",
      remote_text: "Remote",
      location_text: "Brazil",
      stack_tags: [ "react" ]
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    fetcher = FakeFetcher.new(
      "https://career.teamtailor.com/jobs" => jobs_page_html(
        job_url: "https://career.teamtailor.com/jobs/7010130-senior-react-engineer",
        title: "Senior React Engineer",
        department: "Product",
        location: "Brazil",
        work_mode: "Remote",
        next_page: 2
      ),
      "https://career.teamtailor.com/jobs/show_more?page=2" => jobs_show_more_html(
        job_url: "https://career.teamtailor.com/jobs/7010999-product-designer",
        title: "Product Designer",
        department: "Design",
        location: "Brazil",
        work_mode: "Remote"
      ),
      "https://career.teamtailor.com/jobs/7010130-senior-react-engineer" => detail_html(
        title: "Senior React Engineer",
        company_name: "Example Co",
        description: "Remote Brazil React platform role",
        date_posted: 4.days.ago.iso8601
      )
    )

    candidates = JobDiscovery::Adapters::TeamtailorCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Example Co", candidates.first[:company_name]
    assert_equal "7010130", candidates.first[:external_job_id]
    assert_equal "Remote", candidates.first[:remote_text]
    assert_equal "Brazil", candidates.first[:location_text]
  end

  test "rejects stale or inactive teamtailor jobs" do
    source = JobSource.create!(
      name: "Teamtailor Manual",
      slug: "teamtailor-manual",
      host: "teamtailor.com",
      base_url: "https://career.teamtailor.com",
      source_kind: :ats,
      adapter_key: "teamtailor_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "board_urls" => [ "https://career.teamtailor.com" ], "max_pages" => 1 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    fetcher = FakeFetcher.new(
      "https://career.teamtailor.com/jobs" => jobs_page_html(
        job_url: "https://career.teamtailor.com/jobs/7010555-senior-ruby-engineer",
        title: "Senior Ruby Engineer",
        department: "Engineering",
        location: "LatAm",
        work_mode: "Remote"
      ),
      "https://career.teamtailor.com/jobs/7010555-senior-ruby-engineer" => detail_html(
        title: "Senior Ruby Engineer",
        company_name: "Example Co",
        description: "Remote Ruby role",
        date_posted: 45.days.ago.iso8601,
        apply_button: false
      )
    )

    candidates = JobDiscovery::Adapters::TeamtailorCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_empty candidates
  end

  private
    def jobs_page_html(job_url:, title:, department:, location:, work_mode:, next_page: nil)
      next_link = if next_page
        <<~HTML
          <div id="show_more_button" class="flex justify-center mx-auto mt-12">
            <a href="/jobs/show_more?page=#{next_page}" class="careersite-button min-w-[13.75rem] group" data-turbo-stream="true">More jobs</a>
          </div>
        HTML
      else
        ""
      end

      <<~HTML
        <html><body>
          <div class="relative flex flex-col items-center py-6 text-center">
            <a class="@sm:line-clamp-2 flex" data-turbo="false" href="#{job_url}">
              <span class="absolute inset-0"></span>
              #{title}
            </a>
            <div class="mt-1 text-md">
              <span>#{department}</span>
              <span class="mx-[2px]">&middot;</span>
              <span>#{location}</span>
              <span class="mx-[2px]">&middot;</span>
              <span class="inline-flex items-center gap-x-2">#{work_mode}</span>
            </div>
          </div>
          #{next_link}
        </body></html>
      HTML
    end

    def jobs_show_more_html(job_url:, title:, department:, location:, work_mode:)
      <<~HTML
        <turbo-stream action="append" target="jobs_list_container"><template>
          <li class="w-full">
            <div class="relative flex flex-col items-center py-6 text-center">
              <a class="@sm:line-clamp-2 flex" data-turbo="false" href="#{job_url}">
                <span class="absolute inset-0"></span>
                #{title}
              </a>
              <div class="mt-1 text-md">
                <span>#{department}</span>
                <span class="mx-[2px]">&middot;</span>
                <span>#{location}</span>
                <span class="mx-[2px]">&middot;</span>
                <span class="inline-flex items-center gap-x-2">#{work_mode}</span>
              </div>
            </div>
          </li>
        </template></turbo-stream>
        <turbo-stream action="update" target="show_more_button"><template></template></turbo-stream>
      HTML
    end

    def detail_html(title:, company_name:, description:, date_posted:, apply_button: true)
      apply_section = if apply_button
        <<~HTML
          <button role="button" class="careersite-button min-w-[13.75rem] group min-w-[13.75rem] bg-opacity-100">
            <span class="truncate">Apply for this job</span>
          </button>
          <p>Loading application form</p>
        HTML
      else
        "<p>This position has been filled.</p>"
      end

      <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"http://schema.org/","@type":"JobPosting","title":"#{title}","description":"#{description}","datePosted":"#{date_posted}","employmentType":"FULL_TIME","hiringOrganization":{"@type":"Organization","name":"#{company_name}","sameAs":"https://career.teamtailor.com"}}
            </script>
          </head>
          <body>
            #{apply_section}
          </body>
        </html>
      HTML
    end
end
