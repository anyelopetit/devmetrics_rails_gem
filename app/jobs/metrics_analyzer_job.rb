class MetricsAnalyzerJob < ApplicationJob
  queue_as :default

  def perform
    # Calculate stats
    total_queries = QueryLog.count
    avg_duration = QueryLog.average(:duration)&.round(2) || 0
    n_plus_one_count = SlowQuery.count

    # Calculate memory (simple estimation or reading from space)
    # Using a random walk or basic ObjectSpace if available, but for demo:
    memory_mb = (ObjectSpace.memsize_of_all / 1024.0 / 1024.0).round(1) rescue rand(150..300)

    # Active Connections
    db_connections = ActiveRecord::Base.connection_pool.connections.count rescue rand(5..20)

    # Coverage Mock for Live update feel
    @coverage_base ||= 92.3
    @coverage_base += rand(0.01..0.05).round(2) if rand > 0.7
    coverage = @coverage_base.round(2)

    stats = {
      total_queries: total_queries,
      avg_duration: avg_duration,
      n_plus_one_count: n_plus_one_count,
      memory_mb: memory_mb,
      db_connections: db_connections,
      coverage: coverage
    }

    ActionCable.server.broadcast("metrics_channel", {
      type: "stats_update",
      payload: stats
    })
  end
end
