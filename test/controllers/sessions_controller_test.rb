require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "login alias renders new session" do
    get login_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create redirects to the stored relative path after authentication" do
    get jobs_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to jobs_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create redirects first time user to onboarding" do
    user = users(:three)

    post session_path, params: { email_address: user.email_address, password: "password" }

    assert_redirected_to new_search_profile_path(onboarding: 1)
    assert cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "expired session is rejected and destroyed" do
    sign_in_as(@user, expires_at: 1.minute.ago)
    expired_session_id = Current.session.id

    get jobs_path

    assert_redirected_to new_session_path
    assert_nil Session.find_by(id: expired_session_id)
  end

  test "valid session with a future expiry is accepted" do
    sign_in_as(@user, expires_at: 30.days.from_now)

    get jobs_path

    assert_response :success
  end
end
