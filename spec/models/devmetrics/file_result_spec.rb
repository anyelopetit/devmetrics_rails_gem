# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::FileResult, type: :model do
  let(:run) do
    Devmetrics::Run.create!(
      run_id:      SecureRandom.hex(8),
      status:      :running,
      total_files: 1,
      started_at:  Time.current
    )
  end

  describe ".file_key_for" do
    subject(:key) { described_class.file_key_for(file_path) }

    context "with a standard spec path" do
      let(:file_path) { "spec/requests/users_spec.rb" }

      it "returns the basename without .rb extension" do
        expect(key).to eq("users_spec")
      end
    end

    context "with hyphens and uppercase in filename" do
      let(:file_path) { "spec/requests/my-complex_spec.rb" }

      it "replaces non-alphanumeric characters with underscores" do
        expect(key).to eq("my_complex_spec")
      end
    end

    context "with a deeply nested path" do
      let(:file_path) { "/home/user/app/spec/requests/api/v1/orders_spec.rb" }

      it "uses only the basename" do
        expect(key).to eq("orders_spec")
      end
    end
  end

  describe "enum status" do
    subject(:result) do
      described_class.create!(
        run_id:    run.run_id,
        file_key:  "foo_spec",
        file_path: "spec/requests/foo_spec.rb",
        status:    :pending
      )
    end

    it "starts as pending" do
      expect(result).to be_pending
    end

    it "transitions to running" do
      result.running!
      expect(result).to be_running
    end

    it "transitions to passed" do
      result.passed!
      expect(result).to be_passed
    end

    it "transitions to failed" do
      result.failed!
      expect(result).to be_failed
    end
  end

  describe "associations" do
    subject(:result) do
      described_class.create!(
        run_id:    run.run_id,
        file_key:  "foo_spec",
        file_path: "spec/requests/foo_spec.rb",
        status:    :pending
      )
    end

    it "belongs to a run via run_id" do
      expect(result.run).to eq(run)
    end
  end
end
