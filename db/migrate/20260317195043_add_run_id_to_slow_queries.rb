class AddRunIdToSlowQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :slow_queries, :run_id, :string
    add_index :slow_queries, :run_id
  end
end
