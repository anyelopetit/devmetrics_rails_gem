# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::MetricsController, type: :request do
  describe "GET /devmetrics" do
    subject { get "/devmetrics" }

    it "returns 200" do
      subject
      expect(response).to have_http_status(200)
    end
  end

  describe "POST /devmetrics/run_tests" do
    subject { post "/devmetrics/run_tests", headers: { "Content-Type" => "application/json" } }

    context "when the orchestrator succeeds" do
      let(:orchestrator_result) do
        { run_id: "abc123", file_count: 2, files: [{ file_key: "a_spec", display_name: "a_spec.rb" }] }
      end

      before do
        allow(Devmetrics::RunOrchestrator).to receive(:call).and_return(orchestrator_result)
      end

      it "returns 202" do
        subject
        expect(response).to have_http_status(202)
      end

      it "includes the run_id in the response" do
        subject
        expect(JSON.parse(response.body)["run_id"]).to eq("abc123")
      end

      it "includes the files array" do
        subject
        expect(JSON.parse(response.body)["files"]).to be_an(Array)
      end
    end

    context "when the orchestrator returns an error" do
      before do
        allow(Devmetrics::RunOrchestrator).to receive(:call).and_return({ error: "No request specs found" })
      end

      it "returns 422" do
        subject
        expect(response).to have_http_status(422)
      end

      it "includes the error message" do
        subject
        expect(JSON.parse(response.body)["error"]).to eq("No request specs found")
      end
    end
  end

  describe "GET /devmetrics/runs/:run_id/status" do
    let(:run_id) { SecureRandom.hex(8) }

    context "when the run exists" do
      let!(:run) do
        Devmetrics::Run.create!(
          run_id:      run_id,
          status:      :running,
          total_files: 1,
          started_at:  Time.current
        )
      end

      it "returns 200" do
        get "/devmetrics/runs/#{run_id}/status"
        expect(response).to have_http_status(200)
      end

      it "includes the run status" do
        get "/devmetrics/runs/#{run_id}/status"
        expect(JSON.parse(response.body)["status"]).to eq("running")
      end
    end

    context "when the run does not exist" do
      it "returns 404" do
        get "/devmetrics/runs/nonexistent/status"
        expect(response).to have_http_status(404)
      end
    end
  end

  describe "GET /devmetrics/runs/:run_id/logs/:file_key/download" do
    let(:run_id)   { SecureRandom.hex(8) }
    let(:file_key) { "orders_spec" }
    let(:run) do
      Devmetrics::Run.create!(
        run_id:      run_id,
        status:      :completed,
        total_files: 1,
        started_at:  Time.current
      )
    end

    context "when the file result exists with a readable log" do
      let(:tmpfile) { Tempfile.new("orders_spec.log") }

      let!(:result) do
        Devmetrics::FileResult.create!(
          run_id:    run.run_id,
          file_key:  file_key,
          file_path: "spec/requests/orders_spec.rb",
          status:    :passed,
          log_path:  tmpfile.path
        )
      end

      after { tmpfile.unlink }

      it "returns 200 and sends the file" do
        get "/devmetrics/runs/#{run_id}/logs/#{file_key}/download"
        expect(response).to have_http_status(200)
      end
    end

    context "when the file result does not exist" do
      it "returns 404" do
        get "/devmetrics/runs/#{run_id}/logs/missing/download"
        expect(response).to have_http_status(404)
      end
    end

    context "when the file result exists but log file is missing from disk" do
      let!(:result) do
        Devmetrics::FileResult.create!(
          run_id:    run.run_id,
          file_key:  file_key,
          file_path: "spec/requests/orders_spec.rb",
          status:    :passed,
          log_path:  "/tmp/devmetrics_nonexistent_#{SecureRandom.hex}.log"
        )
      end

      it "returns 404" do
        get "/devmetrics/runs/#{run_id}/logs/#{file_key}/download"
        expect(response).to have_http_status(404)
      end
    end
  end
end
