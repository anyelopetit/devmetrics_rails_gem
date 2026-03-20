# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::SqlInstrumentor do
  describe ".around_run" do
    it "sets the thread-local collector during the block" do
      collector_during = nil
      described_class.around_run { collector_during = Thread.current[described_class::THREAD_KEY] }
      expect(collector_during).to include(:queries, :start)
    end

    it "clears the thread-local collector after the block" do
      described_class.around_run { nil }
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end

    it "clears the collector even when the block raises" do
      expect { described_class.around_run { raise "boom" } }.to raise_error("boom")
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end

    it "initializes queries as an empty array" do
      queries_at_start = nil
      described_class.around_run { queries_at_start = Thread.current[described_class::THREAD_KEY][:queries] }
      expect(queries_at_start).to eq([])
    end
  end

  describe ".record" do
    let(:event) do
      instance_double(ActiveSupport::Notifications::Event,
        duration: 42.5,
        payload:  { sql: "SELECT * FROM users" })
    end

    context "when called outside around_run" do
      it "returns nil without recording" do
        expect(described_class.record(event)).to be_nil
      end
    end

    context "when called inside around_run" do
      it "records the query with rounded ms and sql" do
        recorded = nil
        described_class.around_run { recorded = described_class.record(event) }
        expect(recorded).to include(sql: "SELECT * FROM users", ms: 42.5)
      end

      it "includes an iso8601 timestamp" do
        recorded = nil
        described_class.around_run { recorded = described_class.record(event) }
        expect(recorded[:at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end
    end

    context "with transaction control statements" do
      %w[BEGIN COMMIT ROLLBACK SAVEPOINT RELEASE].each do |stmt|
        context "when sql is #{stmt}" do
          let(:event) do
            instance_double(ActiveSupport::Notifications::Event,
              duration: 1.0,
              payload:  { sql: stmt })
          end

          it "does not record the #{stmt} statement" do
            result = nil
            described_class.around_run { result = described_class.record(event) }
            expect(result).to be_nil
          end
        end
      end
    end

    context "when sql has leading/trailing whitespace" do
      let(:event) do
        instance_double(ActiveSupport::Notifications::Event,
          duration: 10.0,
          payload:  { sql: "  SELECT id FROM orders  " })
      end

      it "strips whitespace before recording" do
        recorded = nil
        described_class.around_run { recorded = described_class.record(event) }
        expect(recorded[:sql]).to eq("SELECT id FROM orders")
      end
    end
  end

  describe ".queries" do
    context "when called outside around_run" do
      it "returns an empty array" do
        expect(described_class.queries).to eq([])
      end
    end

    context "when called inside around_run after recording" do
      let(:event) do
        instance_double(ActiveSupport::Notifications::Event,
          duration: 5.0,
          payload:  { sql: "SELECT 1" })
      end

      it "returns the recorded queries" do
        queries = nil
        described_class.around_run do
          described_class.record(event)
          queries = described_class.queries
        end
        expect(queries.size).to eq(1)
        expect(queries.first[:sql]).to eq("SELECT 1")
      end
    end
  end
end
