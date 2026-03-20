require 'bullet'

RSpec.configure do |config|
  config.around(:each, type: :request) do |example|
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name]&.match?(/\A(SCHEMA|TRANSACTION)\z/)
      next if payload[:sql]&.match?(/\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      queries << payload[:sql]
    end

    if defined?(Bullet) && Bullet.enabled?
      Bullet.start_request
    end

    example.run

    if defined?(Bullet) && Bullet.enabled?
      Bullet.end_request
      if Bullet.notification_collector&.notifications_present?
        puts "\n[Bullet] N+1 warnings in: #{example.full_description}"
        Bullet.notification_collector.notifications.each do |notification|
          puts "  #{notification.body}"
        end
      end
    end

    ActiveSupport::Notifications.unsubscribe(subscriber)

    if queries.any?
      puts "\n[SQL] #{queries.size} quer#{queries.size == 1 ? 'y' : 'ies'} in: #{example.full_description}"
      queries.each_with_index do |sql, i|
        puts "  #{i + 1}. #{sql}"
      end
    end
  end
end
