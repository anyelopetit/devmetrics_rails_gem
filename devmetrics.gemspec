Gem::Specification.new do |s|
  s.name        = "devmetrics"
  s.version     = "0.1.0"
  s.authors     = [ "DevMetrics Contributors" ]
  s.email       = []
  s.homepage    = "https://github.com/yourusername/devmetrics"
  s.summary     = "Real-time Rails performance dashboard via Solid Cable"
  s.description = <<~DESC
    DevMetrics is a mountable Rails Engine that adds a live performance
    monitoring dashboard to any Rails 7.1+ application. It tracks slow SQL
    queries, detects N+1 issues via Bullet, streams test run output in real
    time via Solid Cable (no Redis required), and surfaces memory and DB
    connection metrics — all accessible at /devmetrics.
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

  s.add_dependency "rails",           ">= 7.1"
  s.add_dependency "solid_cable",     ">= 3.0"
  s.add_dependency "bullet",          ">= 7.0"
  s.add_dependency "importmap-rails", ">= 2.0.1"
  s.add_dependency "turbo-rails",     ">= 2.0.0"
  s.add_dependency "stimulus-rails",  ">= 1.3.0"
  s.add_dependency "propshaft",       ">= 1.1.0"
end
