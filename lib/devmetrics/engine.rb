module Devmetrics
  class Engine < ::Rails::Engine
    isolate_namespace Devmetrics

    # Specify the layout for namespaced controllers
    config.to_prepare do
      Devmetrics::ApplicationController.layout "devmetrics/application"
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

    # ── Bullet integration ────────────────────────────────────────────────────
    initializer "devmetrics.bullet", after: :load_config_initializers do
      if defined?(Bullet)
        # Bullet setup for standard dev environments
        # Metrics tracking is managed by PerformanceHelpers during test runs
      end
    end
  end
end
