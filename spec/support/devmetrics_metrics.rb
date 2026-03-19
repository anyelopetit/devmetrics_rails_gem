require 'bullet'

module MetricsTracker
  THREAD_KEY = :devmetrics_test_metrics

  def self.capture
    Thread.current[THREAD_KEY] ||= { slow_queries: [], nplusone_issues: [] }
    yield
  ensure
    if Bullet.respond_to?(:notification_collector) && Bullet.notification_collector&.notifications_present?
      Bullet.notification_collector.notifications.each do |notification|
        Thread.current[THREAD_KEY][:nplusone_issues] << notification if notification.type == :n_plus_one_query
      end
    end
    Thread.current[THREAD_KEY] = nil
  end
end

RSpec.configure do |config|
  config.around(:each) do |example|
    if defined?(Bullet) && Bullet.enabled?
      Bullet.start_request
      MetricsTracker.capture { example.run }
      Bullet.end_request
    else
      example.run
    end
  end
end
