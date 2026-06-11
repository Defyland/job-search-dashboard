require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home renders the public Farol landing for anonymous visitors" do
    get root_path

    assert_response :success
    assert_select "title", /Farol/
    assert_match "Vagas certas, sem ruído", response.body
    assert_match "#{JobSources::Catalog.defaults.size} fontes mapeadas", response.body
    assert_match "Todo dia às 08:30 BRT", response.body
    assert_no_match "De hora em hora", response.body
    assert_no_match "25+ fontes", response.body
    assert_no_match "Pronto — você está na lista", response.body
    assert_select "form#capform[aria-disabled=true]"
    assert_select "form#capform input[type=email][disabled][aria-disabled=true][placeholder=?]", "seu@email.com"
    assert_select "form#capform button[disabled][aria-disabled=true]", text: "Em breve"
    assert_select "a[href=?]", new_session_path, text: "Entrar no painel", minimum: 1
  end

  test "home sends authenticated operators straight to the radar" do
    sign_in_as(User.take)

    get root_path

    assert_redirected_to jobs_path
  end
end
