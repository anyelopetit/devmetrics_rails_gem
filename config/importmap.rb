# Engine's own entry point - relies on host app for @hotwired/* and @rails/* pins
pin "devmetrics"

# Explicit pins for folder entry points to allow directory-style imports
pin "devmetrics/controllers", to: "devmetrics/controllers/index.js"
pin "devmetrics/channels", to: "devmetrics/channels/index.js"

# Individual assets within namespaced directories (use absolute path from engine root)
engine_root = File.dirname(__dir__)
pin_all_from File.join(engine_root, "app/javascript/devmetrics/controllers"), under: "devmetrics/controllers"
pin_all_from File.join(engine_root, "app/javascript/devmetrics/channels"), under: "devmetrics/channels"
