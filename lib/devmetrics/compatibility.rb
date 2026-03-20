module Devmetrics
  module Compatibility
    def self.importmap?    = defined?(::Importmap::Engine)
    def self.turbo?        = defined?(::Turbo::Engine)
    def self.stimulus?     = defined?(::Stimulus::Engine)
    def self.propshaft?    = defined?(::Propshaft::Engine)
    def self.bullet?       = defined?(::Bullet)
    def self.solid_cable?  = defined?(::SolidCable)
    def self.hotwire?      = turbo? && stimulus? && importmap?
    def self.rails_version = Gem::Version.new(Rails.version)
  end
end
