RSpec.describe "Devmetrics Dashboard", type: :request do
  describe "GET /devmetrics" do
    it "loads the dashboard" do
      get "/devmetrics"
      expect(response).to have_http_status(200)
    end
  end
end
