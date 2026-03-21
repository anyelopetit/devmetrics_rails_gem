ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rspec/rails'
require 'simplecov'
SimpleCov.start 'rails' do
  enable_coverage :branch
  add_filter '/spec/'
end

config.before(:suite) do
  Rails.env.test? && ActiveRecord::Tasks::DatabaseTasks.drop_current
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
end

require_relative '../spec/support/devmetrics_formatter'
require_relative '../spec/support/devmetrics_metrics'
