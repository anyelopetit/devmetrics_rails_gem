# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devmetrics::LogWriter do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe ".open" do
    subject(:writer) { described_class.open(run_id, file_key) }

    let(:run_id)   { "abc123" }
    let(:file_key) { "users_spec" }

    before { allow(Rails.root).to receive(:join).with("log", "devmetrics", "runs").and_return(Pathname.new(tmpdir)) }

    it "returns a LogWriter instance" do
      expect(writer).to be_a(described_class)
    ensure
      writer.close
    end

    it "creates the run directory" do
      writer
      expect(File.directory?(File.join(tmpdir, run_id))).to be true
    ensure
      writer.close
    end

    it "creates a log file at the expected path" do
      writer
      expect(File.exist?(File.join(tmpdir, run_id, "#{file_key}.log"))).to be true
    ensure
      writer.close
    end
  end

  describe "#path" do
    subject(:writer) { described_class.new(log_path) }

    let(:log_path) { Pathname.new(tmpdir).join("test.log") }

    it "returns the path as a string" do
      expect(writer.path).to eq(log_path.to_s)
    ensure
      writer.close
    end
  end

  describe "#write" do
    subject(:writer) { described_class.new(log_path) }

    let(:log_path) { Pathname.new(tmpdir).join("output.log") }

    it "writes the line to the file with a newline" do
      writer.write("hello world")
      writer.close
      expect(File.read(log_path)).to eq("hello world\n")
    end

    it "flushes immediately so content is readable before close" do
      writer.write("flushed")
      expect(File.read(log_path)).to include("flushed")
    ensure
      writer.close
    end
  end

  describe "#close" do
    subject(:writer) { described_class.new(log_path) }

    let(:log_path) { Pathname.new(tmpdir).join("close_test.log") }

    it "closes the underlying file" do
      io = writer.instance_variable_get(:@file)
      writer.close
      expect(io).to be_closed
    end
  end
end
