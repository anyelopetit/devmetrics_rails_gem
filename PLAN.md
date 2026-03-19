# DevMetrics - MVP Task Plan

- [x] **Phase 1: Project Initialization & DB Setup**
  - [x] Run `rails new devmetrics` with specific flags (Tailwind, PostgreSQL, Stimulus)
  - [x] Configure database and create it (`rails db:create`)
  - [x] Install required gems (bullet, memory_profiler, simplecov)
  - [x] Generate `QueryLog` model (`query:text duration:float user_id:integer`)
  - [x] Generate [SlowQuery](file:///home/starklord/Projects/rails/devmetrics/app/javascript/controllers/metrics_controller.js#52-77) model (`model_name:string line_number:integer fix_suggestion:text`)
  - [x] Run migrations

- [x] **Phase 2: Real-time Infrastructure (Solid Cable)**
  - [x] Install Hotwire (`rails hotwire:install` - already enabled in Rails 8)
  - [x] Install Solid Cable (`rails generate solid_cable:install`)
  - [x] Set up [config/cable.yml](file:///home/starklord/Projects/rails/devmetrics/config/cable.yml) for `solid_queue` adapter (or solid_cable)
  - [x] Generate [Metrics](file:///home/starklord/Projects/rails/devmetrics/app/controllers/metrics_controller.rb#1-9) channel (`rails generate channel Metrics`)

- [x] **Phase 3: Core Logic & Controllers**
  - [x] Create [MetricsController](file:///home/starklord/Projects/rails/devmetrics/app/controllers/metrics_controller.rb#1-9) (Live dashboard view)
  - [x] Create [PlaygroundController](file:///home/starklord/Projects/rails/devmetrics/app/controllers/playground_controller.rb#1-95) (Query executor)
  - [x] Add custom route `/devmetrics`

- [x] **Phase 4: Frontend & Stimulus**
  - [x] Generate Stimulus `metrics` controller for live updates
  - [x] Generate Stimulus `playground` controller for query runner
  - [x] Create views for Dashboard and Playground with Tailwind CSS
  - [x] Implement Dashboard UI (Slow Queries, N+1s, Coverage, Memory, Connections)
  - [x] Implement Playground UI (Query input, live execution results)

- [ ] **Phase 5: Background Processing & Metrics Collection**
  - [x] Set up `MetricsAnalyzerJob` for background perf analysis
  - [ ] Implement N+1 detection logging via Bullet
  - [ ] Implement memory profiling and active connections tracking
  - [ ] Mock or setup SimpleCov live updates

- [ ] **Phase 6: Verification & Polish**
  - [ ] Verify test coverage live updates
  - [ ] Verify N+1 fixes reflect in UI
  - [ ] Verify memory peak usage tracking
  - [ ] Verify live broadcasts work across multiple browser sessions
