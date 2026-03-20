# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::RunOrchestrator do
  describe ".call" do
    subject(:result) { described_class.call }

    before do
      allow(described_class).to receive(:new).and_return(instance)
    end

    let(:instance) { instance_double(described_class, call: { run_id: "abc", file_count: 1, files: [] }) }

    it "delegates to a new instance" do
      result
      expect(instance).to have_received(:call)
    end

    it "returns the instance result" do
      expect(result).to eq({ run_id: "abc", file_count: 1, files: [] })
    end
  end

  describe "#call" do
    subject(:result) { described_class.new.call }

    let(:file_paths) { ["spec/requests/orders_spec.rb", "spec/requests/users_spec.rb"] }
    let(:run) { instance_double(Devmetrics::Run, run_id: "deadbeef12345678", total_files: 2) }

    before do
      allow(Dir).to receive(:glob).and_return(file_paths)
      allow(File).to receive(:read).and_return("")
      allow(Devmetrics::Run).to receive(:create_for_files).and_return(run)
      allow(Devmetrics::FileResult).to receive(:create!).and_return(true)
      allow(ActionCable.server).to receive(:broadcast)
      allow(Devmetrics::FileRunnerJob).to receive(:perform_later)
    end

    context "when spec files are found" do
      it "returns the run_id" do
        expect(result[:run_id]).to eq("deadbeef12345678")
      end

      it "returns the file count" do
        expect(result[:file_count]).to eq(2)
      end

      it "returns file metadata for each file" do
        expect(result[:files].size).to eq(2)
      end

      it "broadcasts run_started on the run stream" do
        result
        expect(ActionCable.server).to have_received(:broadcast).with(
          "devmetrics:run:deadbeef12345678",
          hash_including(type: "run_started", run_id: "deadbeef12345678")
        )
      end

      it "enqueues a FileRunnerJob for each file" do
        result
        expect(Devmetrics::FileRunnerJob).to have_received(:perform_later).twice
      end

      it "creates a FileResult record for each file" do
        result
        expect(Devmetrics::FileResult).to have_received(:create!).twice
      end
    end

    context "when no spec files are found" do
      before { allow(Dir).to receive(:glob).and_return([]) }

      it "returns an error key" do
        expect(result).to have_key(:error)
      end

      it "does not enqueue any jobs" do
        result
        expect(Devmetrics::FileRunnerJob).not_to have_received(:perform_later)
      end
    end

    context "when some files are tagged with devmetrics" do
      let(:tagged_path)   { "spec/requests/tagged_spec.rb" }
      let(:untagged_path) { "spec/requests/plain_spec.rb" }

      before do
        allow(Dir).to receive(:glob).and_return([tagged_path, untagged_path])
        allow(File).to receive(:read).with(tagged_path).and_return("# devmetrics: true")
        allow(File).to receive(:read).with(untagged_path).and_return("# plain spec")
        allow(Devmetrics::Run).to receive(:create_for_files).with([tagged_path]).and_return(run)
      end

      it "runs only the tagged files" do
        result
        expect(Devmetrics::Run).to have_received(:create_for_files).with([tagged_path])
      end
    end
  end
end
