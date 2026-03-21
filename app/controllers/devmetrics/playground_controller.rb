module Devmetrics
  class PlaygroundController < ApplicationController
    def run
      query_string = params[:query]

      unless query_string.present?
        return render json: { status: "error", output: "Empty query" }, status: :unprocessable_entity
      end

      result = nil
      duration = 0
      slow_queries_detected = []

      begin
        # Enable bullet specifically for this block if possible, or track via notifications
        ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
          # Only log SELECT/UPDATE/INSERT/DELETE that aren't schema
          if payload[:sql] !~ /SCHEMA/
            Rails.logger.debug "SQL: #{payload[:sql]}"
          end
        end

        Bullet.start_request if defined?(Bullet)

        duration = Benchmark.ms do
          # Evaluate safely (MVP risk assumed acceptable for demo playground)
          # Using a restricted binding or at least catching standard errors
          # In a real app we'd build an AST or not allow eval, but for this devmetrics demo it's requested
          result = eval(query_string)

          # Force execution if it's an ActiveRecord::Relation
          result = result.to_a if result.is_a?(ActiveRecord::Relation)
        end

        if defined?(Bullet) && Bullet.notification_collector.notifications_present?
          Bullet.notification_collector.collection.each do |notification|
            next unless notification.is_a?(Bullet::Notification::NPlusOneQuery)

            # We parse out the model and association
            model = notification.base_class rescue "Unknown"
            suggestion = notification.body

            sq = Devmetrics::SlowQuery.create!(
              model_class: model,
              line_number: caller.first.match(/:(\d+):/)&.captures&.first&.to_i || 0,
              fix_suggestion: suggestion
            )

            slow_queries_detected << sq

            ActionCable.server.broadcast("devmetrics:metrics", {
              type: "new_slow_query",
              payload: {
                id: sq.id,
                model_class: sq.model_class,
                line_number: sq.line_number,
                fix_suggestion: sq.fix_suggestion,
                duration: duration.round(2)
              }
            })
          end
        end

        Bullet.end_request if defined?(Bullet)

        QueryLog.create(query: query_string, duration: duration) rescue nil

        render json: {
          status: "success",
          duration: duration.round(2),
          output: result.inspect.truncate(1000)
        }
      rescue Exception => e
        Bullet.end_request if defined?(Bullet)
        # Also log failed queries
        QueryLog.create(query: query_string, duration: 0) rescue nil

        render json: {
          status: "error",
          duration: duration.round(2),
          output: "#{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        }
      ensure
        # Unsubscribe if we did
        ActiveSupport::Notifications.unsubscribe("sql.active_record") rescue nil
      end
    end
  end
end
