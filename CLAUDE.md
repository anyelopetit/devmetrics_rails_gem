# Project: DevMetrics (Rails Gem)

You are collaborating on **DevMetrics**, a **Ruby gem** that measures and improves software quality and performance for **Rails 6.1+** applications.
The goal: make it easy for Rails teams to track test quality, performance, and reliability metrics via rake tasks and log analysis.

## Tech Stack

- **Ruby Gem** compatible with **Rails 6.1, 7.x, 8.x**
- Backend: Ruby on Rails (6.1+), PostgreSQL, Sidekiq, Redis
- Metrics collection via rake tasks, log parsing, and RSpec formatter
- CLI-first: `bundle exec rake devmetrics:run`
- Output: JSON logs + optional database storage

## Core Principles

- This is a **gem**, not a Rails app. Support Rails 6.1+ with conditional loading.
- Prefer **small, focused changes** over large rewrites.
- **Plan first, then code**: always propose a short plan before editing multiple files.
- Optimize for **maintainability and observability** over cleverness.
- Assume this is **production‑grade gem software**.

## Token & Context Management

- **Do NOT** paste or reproduce large files or long unchanged sections.
- When you edit a file, show only the **minimal diff** or the smallest relevant region.
- **Avoid adding comments** unless explicitly requested. No docstrings or inline comments by default.
- If asked to "review" a file, focus on **structure, naming, and potential bugs**.
- If context feels noisy, ask to **start a fresh plan** or **narrow scope**.

## Workflow

1. **Understand & Ask**
   - Restate the request briefly.
   - Ask clarifying questions about Rails version compatibility, rake tasks, log formats.

2. **Plan (Short)**
   - Propose 3–7 bullet points referencing concrete gem files (`lib/`, `exe/`, `spec/`).
   - Note Rails version-specific considerations (6.1 vs 7.x vs 8.x).
   - Wait for confirmation before large changes.

3. **Implement**
   - Work in **small steps** (1–2 files or concerns at a time).
   - Respect gem structure: `lib/devmetrics/`, `exe/devmetrics`, `devmetrics.gemspec`.
   - Use `Rails.version` checks for version-specific behavior.

4. **Verify**
   - Suggest gem-specific commands:
     ```
     bundle install
     bundle exec rake spec
     bundle exec rake devmetrics:run
     ```
   - Tests must pass across Rails versions (`rspec`).

5. **Summarize**
   - Files touched, rake task changes, Rails version compatibility notes.

## DevMetrics Domain (Gem)

Core capabilities as a Rails 6.1+ gem:

- RSpec custom formatter writing `devmetrics.log` (test timing, coverage, failures)
- Rake tasks: `devmetrics:run`, `devmetrics:analyze`, `devmetrics:report`
- Log parsing for slow queries (N+1 via Bullet), response times
- Metrics: test coverage, slow tests, query performance, job queue latency

**Data model**: Append-only metrics/events stored as JSON logs or optional DB tables.

## Architecture Preferences

- **Gem structure**:
lib/devmetrics/
├── version.rb
├── engine.rb
├── railtie.rb (Rails 6.1+ Railtie)
├── formatters/
├── rake_tasks/
├── generators/
└── metrics/

- **Rake tasks** for all heavy operations
- **RSpec formatter** as primary data collection point
- Use `ActiveSupport::Dependencies` for conditional loading across Rails versions

## Rails Version Support

- **Rails 6.1**: Basic rake tasks + RSpec formatter
- **Rails 7.x**: Add Solid Queue support, improved Active Record instrumentation
- **Rails 8.x**: Full Turbo/Stimulus integration, Propshaft support
- Use `if Rails.version >= "7.0"` patterns for version-specific features

## Style & Quality

- Follow Ruby gem + Rails conventions (6.1+).
- Gem must work: `bundle add devmetrics`, `rails g devmetrics:install`.
- When refactoring, **preserve rake task behavior** across Rails versions.
- Test version compatibility in `spec/rails_versions/`.
- Offer **2–3 options** with trade-offs if unsure about design.

## When In Doubt

- Ask for:
- `tree lib/` or `rake -T` output
- Specific Rails version constraints
- Current `devmetrics.gemspec` dependencies
- `Rails.version` support matrix

**Support Rails 6.1+ with graceful degradation.**
