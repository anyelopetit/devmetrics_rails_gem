class AddRunIdToQueryLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :query_logs, :run_id, :string
    add_index :query_logs, :run_id
  end
end
