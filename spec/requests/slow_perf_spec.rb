require 'devmetrics'

RSpec.describe "Slow Performance Suite", type: :request, devmetrics: true do
  it "performs a very slow query" do
    ActiveSupport::Notifications.instrument('sql.active_record', sql: 'SELECT pg_sleep(0.5)', start: Time.now - 0.5, finish: Time.now) do
    end
    expect(true).to be true
  end
end
