begin
  require "devmetrics/version"
  require "devmetrics/engine"
rescue LoadError
  # Running as standalone app - engine/version not available
end

require "cgi"
require "benchmark"
require "json"
require "securerandom"

# Core dependencies for the Engine's assets and dashboard
require "importmap-rails"
require "turbo-rails"
require "stimulus-rails"
require "propshaft"
require "bullet"

module Devmetrics
  class Configuration
    attr_accessor :log_file_path, :slow_query_threshold_ms

    def initialize
      @log_file_path = "devmetrics.log"
      @slow_query_threshold_ms = 100
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def setup
      yield(configuration)
    end

    def log_path
      # Use Rails.root if defined (host app), otherwise current dir
      if defined?(Rails) && Rails.root
        Rails.root.join(configuration.log_file_path)
      else
        Pathname.new(configuration.log_file_path)
      end
    end
  end

  module PerformanceHelpers
    def self.setup_test_run!
      return unless ENV["DEVMETRICS_TRACKING"] == "true"

      # Clear and initialize the log file
      File.write(Devmetrics.log_path, "--- DevMetrics Performance Run: #{Time.current} ---\n")

      @total_tests = 0
      @passed_tests = 0
      @failed_tests = 0
      @start_time = Time.current

      # SQL subscriptions
      ActiveSupport::Notifications.subscribe("sql.active_record") do |_, start, finish, _, payload|
        next if payload[:sql] =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET|SHOW|pragma)/i
        next if payload[:name]&.match?(/SCHEMA|ActiveRecord/)

        duration = ((finish - start) * 1000).round(2)
        if duration > Devmetrics.configuration.slow_query_threshold_ms
          Thread.current[:devmetrics_slow_queries] ||= []
          Thread.current[:devmetrics_slow_queries] << { sql: payload[:sql].squish.truncate(100), duration: duration }
        end
      end

      # Controller processing subscriptions
      ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_, start, finish, _, payload|
        Thread.current[:devmetrics_current_action] = {
          controller: payload[:controller],
          action: payload[:action],
          duration: ((finish - start) * 1000).round(2),
          db_runtime: payload[:db_runtime]&.round(2)
        }
      end

      if defined?(Bullet)
        Bullet.enable = true
        Bullet.bullet_logger = true
      end
    end

    def self.log_example_result(example)
      return unless ENV["DEVMETRICS_TRACKING"] == "true"
      @total_tests += 1
      if example.exception
        @failed_tests += 1
      else
        @passed_tests += 1
      end

      action_data = Thread.current[:devmetrics_current_action] || {}
      slow_queries = Thread.current[:devmetrics_slow_queries] || []

      n_plus_one_count = 0
      if defined?(Bullet) && Bullet.notification_collector.notifications_present?
        n_plus_one_count = Bullet.notification_collector.collection.size
      end

      log_row = {
        timestamp: Time.current.strftime("%H:%M:%S"),
        controller: action_data[:controller] || "N/A",
        action: action_data[:action] || "N/A",
        duration_ms: action_data[:duration] || 0.0,
        slow_queries: slow_queries.size,
        n_plus_one_issues: n_plus_one_count,
        status: example.exception ? "FAILED" : "PASSED",
        example: example.full_description.truncate(100)
      }

      File.open(Devmetrics.log_path, "a") { |f| f.puts(log_row.to_json) }

      # Reset state for next example
      Thread.current[:devmetrics_current_action] = nil
      Thread.current[:devmetrics_slow_queries] = nil
      Bullet.notification_collector.clear if defined?(Bullet)
    end

    def self.finish_test_run!
      return unless ENV["DEVMETRICS_TRACKING"] == "true" && @start_time

      total_duration = (Time.current - @start_time).round(3)

      summary = {
        type: "SUMMARY",
        total_time_s: total_duration,
        total_tests: @total_tests,
        passed: @passed_tests,
        failed: @failed_tests,
        timestamp: Time.current.to_s
      }

      File.open(Devmetrics.log_path, "a") do |f|
        f.puts "\n--- Summary ---"
        f.puts summary.to_json
      end
    end
  end
end

# Auto-configure RSpec if present
if defined?(RSpec) && RSpec.respond_to?(:configure)
  RSpec.configure do |config|
    config.before(:suite) do
      Devmetrics::PerformanceHelpers.setup_test_run!
    end

    config.after(:each) do |example|
      Devmetrics::PerformanceHelpers.log_example_result(example)
    end

    config.after(:suite) do
      Devmetrics::PerformanceHelpers.finish_test_run!
    end
  end
end
