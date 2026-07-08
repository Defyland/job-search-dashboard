require "application_system_test_case"

class SubmitStateTest < ApplicationSystemTestCase
  class SlowFakeIntentCompiler
    def initialize(delay: 0.5)
      @delay = delay
    end

    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      sleep @delay

      raise ArgumentError, "expected servicenow stack" unless technology_intent == "servicenow"
      raise ArgumentError, "unexpected seniority" unless seniority_preset == "senior"
      raise ArgumentError, "unexpected language" unless language_scope == "both"
      raise ArgumentError, "unexpected remote flag" unless required_remote == "1" || required_remote == true
      raise ArgumentError, "unexpected region" unless region_scope == "brazil_latam"
      raise ArgumentError, "unexpected women flag" unless include_women_only == "0" || include_women_only == false

      {
        "profile_name_suggestion" => "Senior ServiceNow Remote BR/LatAm",
        "canonical_stacks" => [ "servicenow" ],
        "title_variants_pt" => [ "desenvolvedor servicenow", "engenheiro servicenow" ],
        "title_variants_en" => [ "servicenow developer", "servicenow engineer" ],
        "stack_aliases" => [
          { "canonical_stack" => "servicenow", "aliases" => [ "itsm", "flow designer", "integration hub" ] }
        ],
        "model" => "claude-sonnet-4-20250514",
        "provider" => "anthropic"
      }
    end
  end

  test "non turbo profile compile shows pending state before rendering the preview" do
    with_compiler_available do
      with_fake_intent_compiler(SlowFakeIntentCompiler.new) do
        visit new_session_path
        sign_in_as(users(:one))

        visit new_search_profile_path
        fill_in "Area / stack", with: "ServiceNow"

        capture_submit_snapshot("profile-compile") do
          <<~JS
            const button = document.querySelector("button[name='preview_compile']")
            button.form.addEventListener("submit", () => {
              requestAnimationFrame(() => {
                sessionStorage.setItem("submit-state:profile-compile", JSON.stringify({
                  pending: button.form.dataset.submitStatePending,
                  busy: button.form.getAttribute("aria-busy"),
                  text: button.textContent.trim(),
                  disabled: button.disabled,
                  ariaDisabled: button.getAttribute("aria-disabled"),
                  technologyDisabled: document.querySelector("#search_profile_technology_intent")?.disabled
                }))
              })
            }, { once: true })
            button.click()
          JS
        end

        assert_text(/preview gerado/i)
        assert_text "servicenow developer"

        snapshot = submit_state_snapshot("profile-compile")
        assert_equal "true", snapshot.fetch("pending")
        assert_equal "true", snapshot.fetch("busy")
        assert_equal "Gerando...", snapshot.fetch("text")
        assert_equal true, snapshot.fetch("disabled")
        assert_equal "true", snapshot.fetch("ariaDisabled")
        assert_equal true, snapshot.fetch("technologyDisabled")
      end
    end
  end

  test "turbo backfill submit shows pending state and finishes with a notice" do
    with_slow_action(SearchRunsController, :create) do
      visit new_session_path
      sign_in_as(users(:one))

      visit search_runs_path
      capture_submit_snapshot("runs-backfill") do
        <<~JS
          const button = document.querySelector("input[type='submit'][value='Rodar Rails']")
          button.form.addEventListener("submit", () => {
            requestAnimationFrame(() => {
              sessionStorage.setItem("submit-state:runs-backfill", JSON.stringify({
                pending: button.form.dataset.submitStatePending,
                busy: button.form.getAttribute("aria-busy"),
                text: button.value,
                disabled: button.disabled,
                ariaDisabled: button.getAttribute("aria-disabled")
              }))
            })
          }, { once: true })
          button.click()
        JS
      end

      assert_current_path search_runs_path
      assert_text "Backfill Rails enfileirado para 20 dias."

      snapshot = submit_state_snapshot("runs-backfill")
      assert_equal "true", snapshot.fetch("pending")
      assert_equal "true", snapshot.fetch("busy")
      assert_equal "Enfileirando...", snapshot.fetch("text")
      assert_equal true, snapshot.fetch("disabled")
      assert_equal "true", snapshot.fetch("ariaDisabled")
    end
  end

  test "job state update shows pending state and final success feedback" do
    with_slow_action(JobsController, :mark) do
      visit new_session_path
      sign_in_as(users(:one))

      visit jobs_path(search_profile_id: search_profiles(:default).id)
      capture_submit_snapshot("job-apply") do
        <<~JS
          const row = Array.from(document.querySelectorAll("tbody tr")).find((element) => element.textContent.includes("Frontend Engineer Senior"))
          const button = Array.from(row.querySelectorAll("button, input[type='submit']")).find((element) => {
            const text = element.tagName === "INPUT" ? element.value : element.textContent.trim()
            return text === "Aplicada"
          })
          button.form.addEventListener("submit", () => {
            requestAnimationFrame(() => {
              sessionStorage.setItem("submit-state:job-apply", JSON.stringify({
                pending: button.form.dataset.submitStatePending,
                busy: button.form.getAttribute("aria-busy"),
                text: button.tagName === "INPUT" ? button.value : button.textContent.trim(),
                disabled: button.disabled,
                ariaDisabled: button.getAttribute("aria-disabled")
              }))
            })
          }, { once: true })
          button.click()
        JS
      end

      assert_current_path jobs_path(search_profile_id: search_profiles(:default).id)
      assert_text "Vaga marcada como aplicada."
      assert_equal "applied", job_matches(:react_default).reload.user_state

      snapshot = submit_state_snapshot("job-apply")
      assert_equal "true", snapshot.fetch("pending")
      assert_equal "true", snapshot.fetch("busy")
      assert_equal "Atualizando...", snapshot.fetch("text")
      assert_equal true, snapshot.fetch("disabled")
      assert_equal "true", snapshot.fetch("ariaDisabled")
    end
  end

  test "validation errors restore the submit state on the source form" do
    visit new_session_path
    sign_in_as(users(:one))

    visit edit_source_path(job_sources(:gupy))
    fill_in "Settings (JSON)", with: "{invalid"
    click_button "Salvar fonte"

    assert_text "JSON inválido"
    assert_selector "input[type='submit'][value='Salvar fonte']:not([disabled])"
    assert_no_selector "form[data-submit-state-pending='true']"
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
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

    def with_compiler_available
      original_available = SearchProfiles::CompilerClient.method(:available?)

      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { true }
      yield
    ensure
      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { |*args, **kwargs| original_available.call(*args, **kwargs) }
    end

    def with_slow_action(controller_class, action_name, delay: 0.5)
      original_method = controller_class.instance_method(action_name)

      controller_class.send(:define_method, action_name) do |*args, **kwargs, &block|
        sleep delay
        original_method.bind_call(self, *args, **kwargs, &block)
      end

      yield
    ensure
      controller_class.send(:define_method, action_name, original_method)
    end

    def capture_submit_snapshot(key)
      session_storage_key = "submit-state:#{key}"
      page.execute_script("sessionStorage.removeItem(arguments[0])", session_storage_key)
      page.execute_script(yield)
    end

    def submit_state_snapshot(key)
      session_storage_key = "submit-state:#{key}"
      JSON.parse(page.evaluate_script("sessionStorage.getItem(arguments[0])", session_storage_key))
    end
end
