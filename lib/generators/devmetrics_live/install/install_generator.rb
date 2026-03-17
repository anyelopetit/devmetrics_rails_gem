require "rails/generators"
require "rails/generators/migration"

module DevmetricsLive
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs DevMetrics Live: copies migrations and creates an initializer."

      def self.next_migration_number(dir)
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def create_initializer
        template "initializer.rb", "config/initializers/devmetrics_live.rb"
      end

      def copy_migrations
        migration_template(
          "create_query_logs.rb.erb",
          "db/migrate/create_query_logs.rb",
          migration_version: migration_version
        )
        sleep 1 # Ensure unique timestamps
        migration_template(
          "create_slow_queries.rb.erb",
          "db/migrate/create_slow_queries.rb",
          migration_version: migration_version
        )
      end

      def mount_instructions
        route_exists = File.read("config/routes.rb").include?("devmetrics_live")
        if route_exists
          say "\n  DevMetrics Live is already mounted in config/routes.rb\n", :green
        else
          say "\n  Add this line to your config/routes.rb:\n\n", :yellow
          say "    mount DevmetricsLive::Engine, at: \"/devmetrics\"\n\n", :cyan
          say "  Then visit http://localhost:3000/devmetrics\n\n", :green
        end

        say "  If you use RSpec, tag your request specs to instrument them:\n\n"
        say "    require 'devmetrics_live'\n"
        say "    RSpec.describe 'Posts API', devmetrics_live: true do\n"
        say "      ...\n"
        say "    end\n\n"

        say "  Then run: bin/rails db:migrate\n", :green
      end

      private

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
