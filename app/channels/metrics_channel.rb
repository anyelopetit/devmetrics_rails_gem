class MetricsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "metrics_channel"
  end

  def unsubscribed
    # nothing to clean up
  end
end
