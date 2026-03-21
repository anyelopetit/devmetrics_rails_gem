class AddColumnsToSlowQueries < ActiveRecord::Migration[7.2]
  def change
    add_column :slow_queries, :sql,         :text
    add_column :slow_queries, :duration_ms, :float
    add_column :slow_queries, :file_key,    :string
  end
end
