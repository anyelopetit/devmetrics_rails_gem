require 'rails_helper'
class TestProgressFormatter
  def initialize(output)
    @output = output
    @current_file = nil
    @current_test = nil
    @progress = 0
  end

  def example_started(example)
    @current_test = example.description
    broadcast_progress
  end

  def example_passed(example)
    broadcast_result('pass', example)
  end

  def example_failed(example)
    broadcast_result('fail', example)
  end

  private

  def broadcast_progress
    ActionCable.server.broadcast 'metrics_channel', {
      type: 'test_progress',
      payload: {
        file: @current_file,
        test: @current_test,
        progress: @progress
      }
    }
  end

  def broadcast_result(status, example)
    ActionCable.server.broadcast 'metrics_channel', {
      type: 'test_result',
      payload: {
        status: status,
        description: example.description,
        execution_time: example.execution_time
      }
    }
  end
end

RSpec.configure do |config|
  config.add_formatter TestProgressFormatter
end
