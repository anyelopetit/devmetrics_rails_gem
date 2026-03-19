# DevMetrics — v2 Implementation Plan

## Overview

Three new features on top of the existing MVP:
1. **Performance Test Runner** — CTA button that runs `spec/requests` tests and populates `query_logs` / `slow_queries` from real test performance data.
2. **Live WebSocket Streaming** — Real-time output of the test run broadcast line-by-line via Solid Cable.
3. **Gem Packaging** — Structure the app as a mountable Rails Engine gem (`devmetrics`) with an install generator.

---

## Feature 1 — "Run Performance Tests" Button

### How it works
- User clicks **"Run Performance Tests"** on the dashboard.
- A `POST /devmetrics/run_tests` request enqueues `PerformanceTestRunnerJob`.
- The job:
  1. Scans `spec/requests/**/*.rb` for files that `require 'devmetrics'` or include `Devmetrics::PerformanceHelpers`.
  2. Runs those spec files via `Open3.popen2e('bundle exec rspec <files> --format progress')`.
  3. Instruments every SQL query during the run using `ActiveSupport::Notifications` → records `QueryLog` rows.
  4. Detects N+1s via Bullet (already configured) → records [SlowQuery](file:///home/starklord/Projects/rails/devmetrics/app/javascript/controllers/metrics_controller.js#84-109) rows with fix suggestions.
  5. Broadcasts progress events (start, each test line, summary, end) to [MetricsChannel](file:///home/starklord/Projects/rails/devmetrics/app/channels/metrics_channel.rb#1-10).
- Remove the 5-second polling (`setInterval` in [metrics_controller.js](file:///home/starklord/Projects/rails/devmetrics/app/javascript/controllers/metrics_controller.js)).

### Files to change/add

#### [MODIFY] [metrics_controller.rb](file:///home/starklord/Projects/rails/devmetrics/app/controllers/metrics_controller.rb)
- Add `run_tests` action: validates environment, enqueues `PerformanceTestRunnerJob`, returns `{ status: 'started' }`.

#### [NEW] `app/jobs/performance_test_runner_job.rb`
- Opens subprocess with `Open3.popen2e`.
- Broadcasts each line of output to [MetricsChannel](file:///home/starklord/Projects/rails/devmetrics/app/channels/metrics_channel.rb#1-10) (`type: "test_output"`).
- Uses `ActiveSupport::Notifications` subscriber to measure query time.
- On completion broadcasts `type: "test_complete"` with a summary.

#### [MODIFY] [metrics_channel.rb](file:///home/starklord/Projects/rails/devmetrics/app/channels/metrics_channel.rb)
- Wire up `stream_from "metrics_channel"`.

#### [MODIFY] [routes.rb](file:///home/starklord/Projects/rails/devmetrics/config/routes.rb)
- Add `post '/devmetrics/run_tests', to: 'metrics#run_tests'`.

#### [MODIFY] [metrics/index.html.erb](file:///home/starklord/Projects/rails/devmetrics/app/views/metrics/index.html.erb)
- Add **"Run Performance Tests"** CTA button.
- Add a live terminal-style output panel (hidden by default, shown during/after run).

#### [MODIFY] [metrics_controller.js](file:///home/starklord/Projects/rails/devmetrics/app/javascript/controllers/metrics_controller.js)
- Remove `setInterval` polling.
- Add `handleTestOutput(data)` to stream lines into the terminal panel.
- Add `handleTestComplete(data)` to update stat cards post-run.

---

## Feature 2 — Live WebSocket Terminal Output

### Broadcast Shape
```json
// Each line of test output
{ "type": "test_output", "line": "....F...." }

// Test run complete
{ "type": "test_complete", "payload": { "total_queries": 42, "slow_queries": 3, "avg_duration": 12.3 } }

// Error
{ "type": "test_error", "message": "rspec not found" }
```

### Terminal Panel (in view)
- Appears when run starts, collapsible.
- Dark monospace output area (`bg-gray-950 text-green-400 font-mono`).
- Auto-scrolls to bottom on new lines.
- Status badge: `Running...` → `Done ✓` / `Failed ✗`.

---

## Feature 3 — Rails Engine Gem

### Structure
```
lib/
  devmetrics.rb              # Main entry point + autoloads
  devmetrics/
    engine.rb                     # Rails::Engine, isolate_namespace
    version.rb                    # VERSION = "0.1.0"
    performance_helpers.rb        # Optional test helper for host apps

devmetrics.gemspec           # Gem metadata + dependencies

lib/generators/
  devmetrics/
    install/
      install_generator.rb        # `rails g devmetrics:install`
      templates/
        devmetrics.rb        # initializer template
        migration_template.rb     # Creates query_logs + slow_queries tables
```

### Engine Design
- `isolate_namespace Devmetrics` — no route/model conflicts.
- Routes mounted with `mount ::Devmetrics::Engine, at: '/devmetrics'` in the host app.
- The engine owns all controllers, models, channels, views, and assets.
- Only external dependencies needed in host app: `solid_cable`, `bullet`, `rspec-rails`.

### Install Generator
```bash
rails g devmetrics:install
```
Creates:
1. `config/initializers/devmetrics.rb` (configurable threshold, cable adapter).
2. Migration files for `query_logs` and `slow_queries`.
3. Prints instructions to mount the engine.

### gemspec
```ruby
Gem::Specification.new do |s|
  s.name        = "devmetrics"
  s.version     = ::Devmetrics::VERSION
  s.summary     = "Real-time Rails performance dashboard via Solid Cable"
  s.add_dependency "rails", ">= 7.1"
  s.add_dependency "solid_cable"
  s.add_dependency "bullet"
end
```

---

## Feature 4 — README Update

Remove personal portfolio framing. Document it as a Ruby gem:
- What it does (monitoring, N+1 detection, live test runner)
- Installation (gemspec, mount, generator)
- Configuration options
- Usage of test runner

---

## Verification Plan

### Automated
- `bin/rails runner 'puts ::Devmetrics::VERSION'` — gem loaded.
- `bin/rails g devmetrics:install` — generator produces files.
- POST `/devmetrics/run_tests` → returns 200, job enqueued.

### Manual
- Open `/devmetrics`, click **Run Performance Tests**.
- Watch the terminal panel populate line by line via Solid Cable.
- After run, stat cards update with real data.
