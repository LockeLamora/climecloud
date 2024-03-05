require "test_helper"

class DirectionsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the drections search page successfully when cookie is set' do
    get '/directions'
    assert_response :success
    assert_match 'Directions', @response.body
  end
end
