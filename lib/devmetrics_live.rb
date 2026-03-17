require "devmetrics_live/version"
require "devmetrics_live/engine"

module DevmetricsLive
  class Configuration
    attr_accessor :slow_query_threshold_ms, :max_slow_queries

    def initialize
      @slow_query_threshold_ms = 100
      @max_slow_queries        = 500
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def setup
      yield(configuration)
    end
  end

  # Helper module that host apps can include in their request specs
  # to tag them for the DevMetrics test runner.
  #
  # Usage in spec/requests/posts_spec.rb:
  #   require 'devmetrics_live'
  #   RSpec.describe "Posts", devmetrics_live: true do
  #     ...
  #   end
  #
  module PerformanceHelpers
    # Call this in a before(:suite) or equivalent to auto-instrument
    def self.instrument_if_running!
      run_id = ENV["DEVMETRICS_RUN_ID"]
      return unless run_id

      ActiveSupport::Notifications.subscribe("sql.active_record") do |_, start, finish, _, payload|
        next if payload[:sql] =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET|SHOW|pragma)/i
        next if payload[:name]&.match?(/SCHEMA|ActiveRecord/)

        duration_ms = ((finish - start) * 1000).round(2)
        # Log to DB directly within the test process
        QueryLog.create!(
          query: payload[:sql].squish.truncate(500),
          duration: duration_ms,
          run_id: run_id
        ) rescue nil

        # Print special token for the parent job to intercept and broadcast in real-time
        if duration_ms > 100
          puts "DEVMETRICS_SLOW_QUERY: #{payload[:sql].squish.truncate(200)} | #{duration_ms}ms"
        end
      end
    end
  end
end

# Auto-instrument if we are in a test run with a specified ID
if defined?(Rails) && Rails.env.test? && ENV["DEVMETRICS_RUN_ID"].present?
  DevmetricsLive::PerformanceHelpers.instrument_if_running!
end
