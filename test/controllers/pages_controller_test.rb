require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home renders the public Farol landing for anonymous visitors" do
    get root_path

    assert_response :success
    assert_select "title", /Farol/
    assert_match "Vagas certas, sem ruído", response.body
  end

  test "home sends authenticated operators straight to the radar" do
    sign_in_as(User.take)

    get root_path

    assert_redirected_to jobs_path
  end
end
