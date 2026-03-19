# Pin npm packages by running ./bin/importmap

# Standard pins expected to be provided by host or gem dependencies
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"

# Engine's own entry point
pin "devmetrics"

# Explicit pins for folder entry points to allow directory-style imports
pin "devmetrics/controllers", to: "devmetrics/controllers/index.js"
pin "devmetrics/channels", to: "devmetrics/channels/index.js"

# Individual assets within namespaced directories
pin_all_from "app/javascript/devmetrics/controllers", under: "devmetrics/controllers"
pin_all_from "app/javascript/devmetrics/channels", under: "devmetrics/channels"
