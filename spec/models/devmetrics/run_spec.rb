# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::Run, type: :model do
  describe ".create_for_files" do
    subject(:run) { described_class.create_for_files(file_paths) }

    let(:file_paths) { ["spec/requests/foo_spec.rb", "spec/requests/bar_spec.rb"] }

    it "creates a record with a hex run_id" do
      expect(run.run_id).to match(/\A[0-9a-f]{16}\z/)
    end

    it "sets status to running" do
      expect(run).to be_running
    end

    it "sets total_files to the number of paths" do
      expect(run.total_files).to eq(2)
    end

    it "sets started_at to current time" do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)
      expect(run.started_at.to_i).to eq(freeze_time.to_i)
    end

    it "persists to the database" do
      expect { run }.to change(described_class, :count).by(1)
    end
  end

  describe "enum status" do
    subject(:run) { described_class.create!(run_id: SecureRandom.hex(8), status: :pending, total_files: 1, started_at: Time.current) }

    it "transitions from pending to running" do
      run.running!
      expect(run).to be_running
    end

    it "transitions to completed" do
      run.completed!
      expect(run).to be_completed
    end

    it "transitions to failed" do
      run.failed!
      expect(run).to be_failed
    end
  end

  describe "associations" do
    subject(:run) { described_class.create!(run_id: SecureRandom.hex(8), status: :running, total_files: 1, started_at: Time.current) }

    it "has many file_results" do
      result = Devmetrics::FileResult.create!(
        run_id:    run.run_id,
        file_key:  "foo_spec",
        file_path: "spec/requests/foo_spec.rb",
        status:    :pending
      )
      expect(run.file_results).to include(result)
    end
  end
end
