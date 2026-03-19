module Devmetrics
  class MetricsChannel < ApplicationCable::Channel
    def subscribed
      case params[:stream_type]
      when "run"
        run_id = params[:run_id]
        stream_from "devmetrics:run:#{run_id}" if run_id.present?
      when "file"
        file_key = params[:file_key]
        run_id   = params[:run_id]
        if file_key.present? && run_id.present?
          stream_from "devmetrics:file:#{file_key}:#{run_id}"
        end
      else
        stream_from "devmetrics:metrics"
      end
    end

    def unsubscribed
      stop_all_streams
    end
  end
end
