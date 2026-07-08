require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires password with at least eight characters on create" do
    user = User.new(email_address: "short-password@example.com", password: "short")

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "requires a valid email address" do
    user = User.new(email_address: "sem-arroba", password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email_address], "is invalid"
  end
end
