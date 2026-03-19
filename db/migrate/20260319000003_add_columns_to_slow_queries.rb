class AddColumnsToSlowQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :slow_queries, :sql,         :text
    add_column :slow_queries, :duration_ms, :float
    add_column :slow_queries, :file_key,    :string
  end
end
