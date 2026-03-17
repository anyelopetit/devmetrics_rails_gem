module DevmetricsLive
  class Engine < ::Rails::Engine
    isolate_namespace DevmetricsLive

    # ── Asset & View configuration ───────────────────────────────────────────
    initializer "devmetrics_live.assets" do |app|
      app.config.assets.paths << root.join("app", "assets") if app.config.respond_to?(:assets)
    end

    # ── Action Cable subscription adapter passthrough ─────────────────────────
    initializer "devmetrics_live.action_cable" do
      ActiveSupport.on_load(:action_cable) do
        # Nothing extra needed — the engine's MetricsChannel is loaded automatically
      end
    end

    # ── Bullet integration ────────────────────────────────────────────────────
    initializer "devmetrics_live.bullet", after: :load_config_initializers do
      if defined?(Bullet)
        Bullet.enable     ||= true
        Bullet.bullet_logger = true
        Bullet.add_footer    = false
      end
    end
  end
end
