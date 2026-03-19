module Devmetrics
  class SlowQuery < ActiveRecord::Base
    self.table_name = "slow_queries"
  end
end
