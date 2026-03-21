class CreateQueryLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :query_logs do |t|
      t.text :query
      t.float :duration
      t.integer :user_id

      t.timestamps
    end
  end
end
