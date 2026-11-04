require "application_system_test_case"
require "fileutils"

class JobsTest < ApplicationSystemTestCase
  # Form login and market pages can exceed Capybara's 2s default on a loaded machine (a 302 login took 1.5s server-side).
  setup do
    @default_max_wait_time = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 10
  end

  teardown do
    Capybara.default_max_wait_time = @default_max_wait_time
  end

  test "mobile radar renders jobs as cards instead of a wide table" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit jobs_path(search_profile_id: search_profiles(:default).id, user_state: :all)

    assert_text "Radar de vagas"
    assert_selector "[data-testid='filtered-results-summary']", text: "2 vagas retornadas"
    assert_selector "[data-testid='mobile-job-list']", visible: true
    assert_no_selector "[data-testid='desktop-job-table']", visible: true

    summary_top = page.evaluate_script("document.querySelector('[data-testid=\"filtered-results-summary\"]').getBoundingClientRect().top")
    list_top = page.evaluate_script("document.querySelector('[data-testid=\"mobile-job-list\"]').getBoundingClientRect().top")
    assert_operator summary_top, :<, list_top

    within "[data-testid='mobile-job-list']" do
      assert_link "Frontend Engineer Senior"
      assert_text "Memed"
      assert_text "Trabalho remoto"
      assert_text "Gupy"
      assert_link "Detalhes"
      assert_button "Abrir"
      assert_button "Vista"
      assert_button "Aplicada"
      assert_button "Ignorar"
    end
  end

  test "mobile job details show captured description and match context" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)

    assert_text "Frontend Engineer Senior"
    assert_text "Leia a vaga sem sair do radar"
    assert_text(/por que deu match/i)
    assert_text "Desenvolver interfaces React"
    assert_text "Experiencia com React"
    assert_text "Trabalho remoto no Brasil"
    assert_text(/link original/i)
    assert_button "Abrir candidatura"
  end

  test "market E2E: Nacionais shows 27 real national matches over two pages and survives reload" do
    seed_market_profile
    use_desktop_window
    sign_in_with_form(users(:one))

    visit market_radar_path(market: "national")

    assert_selector "[data-testid='filtered-results-summary']", text: "27 vagas retornadas"
    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 1-25 nesta pagina."
    assert_equal "Nacionais", active_market
    assert_selector "input[name='market'][value='national']", visible: :all
    assert_no_selector "[data-testid='unknown-market-notice']"
    assert_equal numbered_titles("Vaga Nacional", 1..25), listed_titles

    assert_selector "a[href*='page=2'][href*='market=national']"
    find("a[href*='page=2']").click

    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 26-27 nesta pagina."
    assert_text "Pagina 2 de 2"
    assert_equal "Nacionais", active_market
    assert_equal numbered_titles("Vaga Nacional", 26..27), listed_titles

    url_before_reload = page.current_url
    query_before_reload = current_query
    assert_equal(
      { "search_profile_id" => @profile.id.to_s, "user_state" => "all", "sort" => "company", "market" => "national", "page" => "2" },
      query_before_reload
    )

    page.refresh

    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 26-27 nesta pagina."
    assert_equal url_before_reload, page.current_url
    assert_equal query_before_reload, current_query
    assert_equal numbered_titles("Vaga Nacional", 26..27), listed_titles
    assert_equal "Nacionais", active_market
    assert_selector "input[name='market'][value='national']", visible: :all
  end

  test "market E2E: Internacionais, Todas and Filtrar keep market and profile without leaking another user" do
    seed_market_profile
    seed_other_user_profile
    use_desktop_window
    sign_in_with_form(users(:one))

    visit market_radar_path(market: "national")
    assert_selector "[data-testid='filtered-results-summary']", text: "27 vagas retornadas"
    find("a[href*='page=2']").click
    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 26-27 nesta pagina."

    click_market_tab "Internacionais"

    assert_selector "[data-testid='filtered-results-summary']", text: "3 vagas retornadas"
    assert_equal "Internacionais", active_market
    assert_includes [ nil, "1" ], current_query["page"]
    assert_equal @profile.id.to_s, current_query["search_profile_id"]
    assert_equal "all", current_query["user_state"]
    assert_equal "company", current_query["sort"]
    assert_equal "international", current_query["market"]
    assert_equal numbered_titles("Vaga Internacional", 1..3), listed_titles
    assert_no_selector "[data-testid='unknown-market-notice']"

    click_market_tab "Todas"

    assert_selector "[data-testid='filtered-results-summary']", text: "32 vagas retornadas"
    assert_equal "Todas", active_market
    refute current_query.key?("market")
    assert_no_selector "input[name='market']", visible: :all
    assert_equal "2 sem mercado identificado", unknown_market_notice

    find("a[href*='page=2']").click
    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 26-32 nesta pagina."
    assert_equal numbered_titles("Vaga Nacional", 23..27) + numbered_titles("Vaga Sem Mercado", 1..2), listed_titles

    visit market_radar_path(q: "Sem Mercado")

    assert_selector "[data-testid='filtered-results-summary']", text: "2 vagas retornadas"
    assert_equal numbered_titles("Vaga Sem Mercado", 1..2), listed_titles
    assert_equal "2 sem mercado identificado", unknown_market_notice

    visit market_radar_path(q: "Vazamento")

    assert_selector "[data-testid='filtered-results-summary']", text: "0 vagas retornadas"
    assert_no_selector "[data-testid='unknown-market-notice']"

    visit market_radar_path(market: "national")
    click_market_tab "Nacionais"
    assert_selector "[data-testid='filtered-results-summary']", text: "27 vagas retornadas"
    find("a[href*='page=2']").click
    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 26-27 nesta pagina."

    # Filtrar from page 2 must land on page 1 with market kept; waiting for "Mostrando 1-25"
    # (only true after the submit) avoids reading the old page, which also shows 27 results.
    click_button "Filtrar"

    assert_selector "[data-testid='filtered-results-summary']", text: "Mostrando 1-25 nesta pagina."
    assert_selector "[data-testid='filtered-results-summary']", text: "27 vagas retornadas"
    assert_equal "Nacionais", active_market
    assert_equal "national", current_query["market"]
    assert_equal @profile.id.to_s, current_query["search_profile_id"]
    assert_equal @profile.id.to_s, find("select[name='search_profile_id']").value
    assert_equal numbered_titles("Vaga Nacional", 1..25), listed_titles
    assert_selector "input[name='market'][value='national']", visible: :all

    click_link "Aplicadas"

    assert_selector "[data-testid='filtered-results-summary']", text: "0 vagas retornadas"
    assert_equal "applied", current_query["user_state"]
    assert_equal "national", current_query["market"]
    assert_equal @profile.id.to_s, current_query["search_profile_id"]
    refute current_query.key?("page")
  end

  test "market group screenshots at mobile, tablet and desktop widths" do
    skip "Set UI_SCREENSHOTS=1 to capture market screenshots" unless ENV["UI_SCREENSHOTS"] == "1"

    seed_market_profile
    sign_in_with_form(users(:one))

    screenshot_dir = Rails.root.join("tmp/pair-discovery-markets/ui2")
    FileUtils.mkdir_p(screenshot_dir)

    [ [ 390, 844 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      visit market_radar_path(market: "national")

      assert_selector "[data-testid='filtered-results-summary']", text: "27 vagas retornadas"
      assert_selector "[data-testid='market-filter'] a[aria-current='page']", text: "Nacionais"

      group = find("[data-testid='market-filter']")
      page.scroll_to(group, align: :center)

      page.save_screenshot(screenshot_dir.join("#{width}x#{height}-viewport.png").to_s)
      File.binwrite(screenshot_dir.join("#{width}x#{height}-market-group.png"), group.native.screenshot_as(:png))
    end
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
    end

    # Wait for the current Turbo visit to finish before navigating to another market.
    def click_market_tab(label)
      assert_no_selector "html[aria-busy='true']", visible: :all
      within "[data-testid='market-filter']" do
        click_link label
      end
    end

    def use_desktop_window
      # Mobile tests share the browser window, so table checks need an explicit resize.
      page.driver.browser.manage.window.resize_to(1440, 1000)
    end

    def sign_in_with_form(user)
      visit new_session_path
      fill_in "Email", with: user.email_address
      fill_in "Senha", with: "password"
      click_button "Acessar painel"

      assert_no_current_path new_session_path
      assert_no_text "Email ou senha invalidos"
    end

    def market_radar_path(**params)
      jobs_path({ search_profile_id: @profile.id, user_state: "all", sort: "company" }.merge(params))
    end

    def seed_market_profile
      @profile = users(:one).search_profiles.create!(name: "Mercado E2E Radar")

      (1..27).each do |number|
        create_market_match(@profile, title: numbered("Vaga Nacional", number), company: numbered("Empresa Nacional", number), location: "Brasil", sequence: number)
      end
      (1..3).each do |number|
        create_market_match(@profile, title: numbered("Vaga Internacional", number), company: numbered("Empresa Internacional", number), location: "Worldwide", sequence: 30 + number)
      end
      (1..2).each do |number|
        create_market_match(@profile, title: numbered("Vaga Sem Mercado", number), company: numbered("Empresa Sem Mercado", number), location: "Remote", sequence: 40 + number)
      end
    end

    def seed_other_user_profile
      profile = users(:two).search_profiles.create!(name: "Perfil Vazamento Two")

      create_market_match(profile, title: "Vaga Vazamento Nacional", company: "Empresa Vazamento Nacional", location: "Brasil", sequence: 60)
      create_market_match(profile, title: "Vaga Vazamento Remota", company: "Empresa Vazamento Remota", location: "Remote", sequence: 61)
    end

    # Market is derived from location/remote text by Job's before_validation callback, so rows only
    # set those texts and never pass market: directly.
    def create_market_match(profile, title:, company:, location:, sequence:)
      slug = title.parameterize
      url = "https://gupy.io/e2e-mercado/#{slug}"

      job = Job.create!(
        job_source: job_sources(:gupy),
        title:,
        company_name: company,
        apply_url: url,
        canonical_url: url,
        source_url: url,
        ats_name: "Gupy",
        external_job_id: slug,
        location_text: location,
        remote_text: location,
        lifecycle_state: :active,
        posted_text: "publicada ha 1 dia",
        published_at: Time.zone.local(2026, 10, 1, 9) + sequence.hours,
        fingerprint: "e2e-mercado::#{slug}"
      )

      JobMatch.create!(
        search_profile: profile,
        job:,
        match_strength: :strong,
        user_state: :new_match,
        score: 80,
        reason: "Match E2E #{title}",
        stack_tags: %w[ruby react],
        eligibility_flags: []
      )
    end

    def numbered(prefix, number)
      format("%s %02d", prefix, number)
    end

    def numbered_titles(prefix, range)
      range.map { |number| numbered(prefix, number) }
    end

    def listed_titles
      page.all("[data-testid='desktop-job-table'] tbody tr td:first-child a").map(&:text)
    end

    def active_market
      find("[data-testid='market-filter'] a[aria-current='page']").text
    end

    def unknown_market_notice
      find("[data-testid='unknown-market-notice']").text
    end

    def current_query
      URI.decode_www_form(URI.parse(page.current_url).query.to_s).to_h
    end
end
