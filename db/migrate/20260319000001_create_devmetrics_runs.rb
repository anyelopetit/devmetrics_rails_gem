class CreateDevmetricsRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :devmetrics_runs do |t|
      t.string   :run_id,          null: false
      t.integer  :status,          default: 0, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer  :total_files,     default: 0
      t.integer  :completed_files, default: 0

      t.timestamps
    end

    add_index :devmetrics_runs, :run_id, unique: true
  end
end
