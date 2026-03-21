module Devmetrics
  class SqlInstrumentor
    THREAD_KEY = :devmetrics_sql_collector

    def self.around_run
      Thread.current[THREAD_KEY] = { queries: [], start: Time.current }
      yield
    ensure
      Thread.current[THREAD_KEY] = nil
    end

    def self.record(event)
      collector = Thread.current[THREAD_KEY]
      return unless collector

      ms  = event.duration.round(2)
      sql = event.payload[:sql].to_s.strip

      return if sql.match?(/\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      collector[:queries] << { sql: sql, ms: ms, at: Time.current.iso8601 }
      collector[:queries].last
    end

    def self.queries
      Thread.current[THREAD_KEY]&.dig(:queries) || []
    end
  end
end
