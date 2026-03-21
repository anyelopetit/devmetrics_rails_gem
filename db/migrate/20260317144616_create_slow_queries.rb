class CreateSlowQueries < ActiveRecord::Migration[7.2]
  def change
    create_table :slow_queries do |t|
      t.string :model_class
      t.integer :line_number
      t.text :fix_suggestion

      t.timestamps
    end
  end
end
