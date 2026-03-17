require 'rails_helper'
require 'devmetrics_live'

RSpec.describe "Performance Suite", type: :request, devmetrics_live: true do
  it "performs a slow query" do
    # Trigger a dummy slow query if possible or just use sleep + notification
    ActiveSupport::Notifications.instrument('sql.active_record', sql: 'SELECT * FROM users OFFSET 5000', start: Time.now - 0.2, finish: Time.now) do
      # nothing
    end
    expect(true).to be true
  end

  it "performs another query" do
    ActiveSupport::Notifications.instrument('sql.active_record', sql: 'SELECT count(*) FROM query_logs', start: Time.now - 0.05, finish: Time.now) do
    end
    expect(true).to be true
  end
end
