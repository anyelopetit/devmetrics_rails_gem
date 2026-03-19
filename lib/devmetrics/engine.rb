module Devmetrics
  class Engine < ::Rails::Engine
    isolate_namespace Devmetrics

    # Use a dedicated routes file so config/routes.rb can be the host-app routes
    paths["config/routes.rb"] = "config/engine_routes.rb"

    config.to_prepare do
      Devmetrics::ApplicationController.layout "devmetrics/application"

      require "devmetrics/log_writer"
      require "devmetrics/sql_instrumentor"
      require "devmetrics/run_orchestrator"
    end

    # ── Asset & View configuration ───────────────────────────────────────────
    initializer "devmetrics.importmap", after: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << root.join("app/javascript")
      end
    end

    # ── Action View Helpers ──────────────────────────────────────────────────
    initializer "devmetrics.helpers" do
      ActiveSupport.on_load(:action_view) do
        if defined?(::Importmap::ImportmapTagsHelper)
          include ::Importmap::ImportmapTagsHelper
        end

        if defined?(::Turbo::FramesHelper)
          include ::Turbo::FramesHelper
        end
      end
    end

    initializer "devmetrics.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/javascript")
      end
    end

    initializer "devmetrics.sql_notifications" do
      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        Devmetrics::SqlInstrumentor.record(event) if defined?(Devmetrics::SqlInstrumentor)
      end
    end
  end
end
