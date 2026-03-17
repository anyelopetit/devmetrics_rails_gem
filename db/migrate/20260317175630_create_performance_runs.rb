class CreatePerformanceRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :performance_runs do |t|
      t.string :run_id
      t.integer :total_files
      t.integer :completed_files
      t.string :status

      t.timestamps
    end
  end
end
