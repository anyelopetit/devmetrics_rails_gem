# DevMetrics Live

**DevMetrics Live** is a mountable Rails Engine gem that adds a real-time performance monitoring dashboard to any Rails 7.1+ application. It surfaces slow SQL queries, detects N+1 issues, streams test run output via ActionCable (Solid Cable, no Redis), and shows memory and DB connection metrics — all at a configurable route.

---

## Features

- **Live Performance Dashboard** at `/devmetrics` — updates on every test run via Solid Cable WebSocket broadcasts.
- **Run Performance Tests** — one-click button that scans `spec/requests/` for request specs, runs them via RSpec, and streams every line of output to the browser in real time.
- **Automatic SQL Instrumentation** — every query during a test run is timed with `ActiveSupport::Notifications` and logged to `query_logs`.
- **N+1 Detection** — integrates with [Bullet](https://github.com/flyerhzm/bullet). Detected N+1 issues are stored in `slow_queries` and shown with fix suggestions.
- **Memory & Connection Monitoring** — reports current process memory and DB connection pool usage.
- **No Redis required** — powered by [Solid Cable](https://github.com/rails/solid_cable) (database-backed ActionCable).
- **Interactive Query Playground** at `/devmetrics/playground` — execute arbitrary ActiveRecord code and see performance impact immediately.

---

## Requirements

- Ruby >= 3.1
- Rails >= 7.1
- PostgreSQL (or any ActiveRecord-compatible DB)
- `solid_cable` gem
- `bullet` gem
- `rspec-rails` gem (for the test runner feature)

---

## Installation

### 1. Add to your Gemfile

```ruby
# Gemfile
gem "devmetrics_live", path: "/path/to/devmetrics_live"  # local gem
# or once published:
# gem "devmetrics_live"
```

### 2. Run the install generator

```bash
bundle install
rails g devmetrics_live:install
rails db:migrate
```

The generator creates:
- `config/initializers/devmetrics_live.rb` — optional configuration
- Migration files for `query_logs` and `slow_queries` tables

### 3. Mount the engine

In `config/routes.rb`:

```ruby
mount DevmetricsLive::Engine, at: "/devmetrics"
```

### 4. Add Solid Cable (if not already configured)

```bash
rails generate solid_cable:install
```

### 5. Start the server

```bash
bin/dev
```

Visit **http://localhost:3000/devmetrics**

---

## Configuration

```ruby
# config/initializers/devmetrics_live.rb
DevmetricsLive.setup do |config|
  config.slow_query_threshold_ms = 100   # Log queries slower than 100ms
  config.max_slow_queries        = 500   # Keep at most 500 slow query records
end
```

---

## Using the Test Runner

The **"Run Performance Tests"** button on the dashboard will:

1. Scan `spec/requests/` for files that `require 'devmetrics_live'` (or fall back to all request specs if none are tagged).
2. Run them via `bundle exec rspec --format documentation`.
3. Instrument every SQL query and broadcast each output line to the dashboard in real time.
4. Store slow queries and N+1 detections. Update the stat cards when the run completes.

### Tagging specs for DevMetrics

```ruby
# spec/requests/posts_spec.rb
require 'devmetrics_live'

RSpec.describe "Posts", devmetrics_live: true do
  it "lists posts efficiently" do
    get "/posts"
    expect(response).to have_http_status(:success)
  end
end
```

Any file containing `devmetrics_live` (the string or `require`) will be picked up by the runner. Files without the tag are skipped unless no tagged files exist, in which case all request specs run.

---

## How It Works

```
Browser opens /devmetrics
  → subscribes to MetricsChannel via Solid Cable

User clicks "Run Performance Tests"
  → POST /devmetrics/run_tests
  → MetricsController enqueues PerformanceTestRunnerJob

PerformanceTestRunnerJob (background)
  → Open3.popen2e("bundle exec rspec spec/requests/...")
  → ActiveSupport::Notifications subscriber instruments each SQL query
  → Broadcasts each RSpec output line: { type: "test_output", line: "..." }
  → On N+1 detection: creates SlowQuery + broadcasts { type: "new_slow_query" }
  → On completion: broadcasts { type: "test_run_complete", payload: { stats } }

Browser receives broadcasts
  → Stimulus metrics_controller.js appends lines to the live terminal panel
  → Stat cards (queries, avg duration, N+1s) update
```

---

## Dashboard Routes

| Path | Description |
|---|---|
| `GET /devmetrics` | Main performance dashboard |
| `GET /devmetrics/playground` | Interactive query executor |
| `POST /devmetrics/run_tests` | Trigger test runner (JSON) |
| `POST /devmetrics/playground` | Execute a query (JSON) |

---

## Development

Clone the repo and run the included Rails app:

```bash
git clone <repo>
cd devmetrics_live
bundle install
rails db:create db:migrate
bin/dev
```

Open http://localhost:3000/devmetrics.

---

## License

MIT
