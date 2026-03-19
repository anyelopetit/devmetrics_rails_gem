RSpec.describe "Devmetrics Dashboard", type: :request do
  describe "GET /" do
    it "loads the dashboard" do
      get "/"
      expect(response).to have_http_status(200)
    end
  end
end
