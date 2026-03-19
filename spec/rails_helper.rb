ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rspec/rails'
require 'simplecov'
SimpleCov.start 'rails' do
  enable_coverage :branch
  add_filter '/spec/'
end

require_relative '../spec/support/devmetrics_formatter'
require_relative '../spec/support/devmetrics_metrics'
