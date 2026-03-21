Gem::Specification.new do |s|
  s.name        = "devmetrics"
  s.version     = "0.1.0"
  s.authors     = [ "DevMetrics Contributors" ]
  s.email       = []
  s.homepage    = "https://github.com/yourusername/devmetrics"
  s.summary     = "Real-time Rails performance dashboard"
  s.description = <<~DESC
    DevMetrics is a mountable Rails Engine that adds a live performance
    monitoring dashboard to any Rails 6.1+ application. It tracks slow SQL
    queries, detects N+1 issues via Bullet, streams test run output in real
    time, and surfaces memory and DB connection metrics — all accessible at /devmetrics.
  DESC
  s.license  = "MIT"
  s.files    = Dir[
    "app/**/*",
    "config/**/*",
    "db/migrate/**/*",
    "lib/**/*",
    "{README,CHANGELOG,LICENSE}.md"
  ]

  # Rails Engine must require the engine
  s.require_paths = [ "lib" ]

  s.required_ruby_version = ">= 3.1"

  s.add_dependency "rails", ">= 6.1"
end
