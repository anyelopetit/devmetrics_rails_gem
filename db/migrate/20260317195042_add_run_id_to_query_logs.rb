class AddRunIdToQueryLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :query_logs, :run_id, :string
    add_index :query_logs, :run_id
  end
end
