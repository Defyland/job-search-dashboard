require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get sources_path
    assert_response :success
  end
end
