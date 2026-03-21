class AddRunIdToSlowQueries < ActiveRecord::Migration[7.2]
  def change
    add_column :slow_queries, :run_id, :string
    add_index :slow_queries, :run_id
  end
end
