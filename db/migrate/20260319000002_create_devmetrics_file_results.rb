class CreateDevmetricsFileResults < ActiveRecord::Migration[7.2]
  def change
    create_table :devmetrics_file_results do |t|
      t.string  :run_id,           null: false
      t.string  :file_key,         null: false
      t.string  :file_path
      t.integer :status,           default: 0, null: false
      t.integer :total_tests,      default: 0
      t.integer :passed_tests,     default: 0
      t.integer :failed_tests,     default: 0
      t.integer :slow_query_count, default: 0
      t.integer :n1_count,         default: 0
      t.float   :coverage
      t.integer :duration_ms
      t.string  :log_path

      t.timestamps
    end

    add_index :devmetrics_file_results, :run_id
    add_index :devmetrics_file_results, [ :run_id, :file_key ], unique: true
  end
end
