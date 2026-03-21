# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devmetrics Dashboard", type: :request do
  describe "GET /devmetrics" do
    it "returns 200 and renders the dashboard" do
      get "/devmetrics"
      expect(response).to have_http_status(200)
    end
  end
end
