require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders signup form" do
    get new_registration_path

    assert_response :success
    assert_select "form[action=?]", registration_path
    assert_select "input[name=?][type=email]", "user[email_address]"
    assert_select "input[name=?][type=password]", "user[password]"
    assert_select "input[name=?][type=password]", "user[password_confirmation]"
  end

  test "create registers and signs in new user" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { Session.count }, 1 do
        post registration_path, params: {
          user: {
            email_address: " NewUser@example.com ",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
    end

    user = User.order(:created_at).last
    assert_equal "newuser@example.com", user.email_address
    assert_redirected_to new_search_profile_path(onboarding: 1)
    assert cookies[:session_id]
  end

  test "create rejects invalid signup" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { Session.count } do
        post registration_path, params: {
          user: {
            email_address: users(:one).email_address,
            password: "short",
            password_confirmation: "different"
          }
        }
      end
    end

    assert_response :unprocessable_entity
    assert_nil cookies[:session_id]
  end

  test "new redirects authenticated user" do
    sign_in_as(users(:one))

    get new_registration_path

    assert_redirected_to root_path
  end

  test "create redirects authenticated user without creating another account" do
    sign_in_as(users(:one))

    assert_no_difference -> { User.count } do
      assert_no_difference -> { Session.count } do
        post registration_path, params: {
          user: {
            email_address: "other@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
    end

    assert_redirected_to root_path
  end
end
