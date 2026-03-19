# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_19_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "devmetrics_file_results", force: :cascade do |t|
    t.string "run_id", null: false
    t.string "file_key", null: false
    t.string "file_path"
    t.integer "status", default: 0, null: false
    t.integer "total_tests", default: 0
    t.integer "passed_tests", default: 0
    t.integer "failed_tests", default: 0
    t.integer "slow_query_count", default: 0
    t.integer "n1_count", default: 0
    t.float "coverage"
    t.integer "duration_ms"
    t.string "log_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "file_key"], name: "index_devmetrics_file_results_on_run_id_and_file_key", unique: true
    t.index ["run_id"], name: "index_devmetrics_file_results_on_run_id"
  end

  create_table "devmetrics_runs", force: :cascade do |t|
    t.string "run_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "total_files", default: 0
    t.integer "completed_files", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_devmetrics_runs_on_run_id", unique: true
  end

  create_table "performance_runs", force: :cascade do |t|
    t.string "run_id"
    t.integer "total_files"
    t.integer "completed_files"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "query_logs", force: :cascade do |t|
    t.text "query"
    t.float "duration"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "run_id"
    t.index ["run_id"], name: "index_query_logs_on_run_id"
  end

  create_table "slow_queries", force: :cascade do |t|
    t.string "model_class"
    t.integer "line_number"
    t.text "fix_suggestion"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "run_id"
    t.text "sql"
    t.float "duration_ms"
    t.string "file_key"
    t.index ["run_id"], name: "index_slow_queries_on_run_id"
  end
end
