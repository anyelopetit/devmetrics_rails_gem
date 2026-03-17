require "test_helper"

class PlaygroundControllerTest < ActionDispatch::IntegrationTest
  test "should get run" do
    get playground_run_url
    assert_response :success
  end
end
