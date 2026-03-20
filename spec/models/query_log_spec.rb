# frozen_string_literal: true

require "rails_helper"

RSpec.describe QueryLog, type: :model do
  describe "#initialize" do
    subject(:instance) { described_class.new(query: "SELECT 1") }

    it "stores the query attribute" do
      expect(instance.query).to eq("SELECT 1")
    end
  end

  describe "validations" do
    subject(:log) { described_class.new(query: "SELECT * FROM users", duration: 150, user_id: 1) }

    it "is valid with basic attributes" do
      expect(log).to be_valid
    end
  end
end
