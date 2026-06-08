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

ActiveRecord::Schema[8.1].define(version: 2026_06_08_013000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "discovered_jobs", force: :cascade do |t|
    t.string "apply_url"
    t.string "canonical_url"
    t.integer "classification", default: 0, null: false
    t.string "company_name"
    t.datetime "created_at", null: false
    t.text "exclusion_reason"
    t.string "external_job_id"
    t.string "fingerprint", null: false
    t.bigint "job_id"
    t.bigint "job_source_id", null: false
    t.string "location_text"
    t.jsonb "payload", default: {}, null: false
    t.string "posted_text"
    t.datetime "published_at"
    t.text "reason"
    t.string "remote_text"
    t.integer "score", default: 0, null: false
    t.bigint "search_run_id", null: false
    t.string "seniority", default: "senior", null: false
    t.bigint "source_scan_id", null: false
    t.string "source_url"
    t.text "stack_tags", default: [], null: false, array: true
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["canonical_url"], name: "index_discovered_jobs_on_canonical_url"
    t.index ["classification"], name: "index_discovered_jobs_on_classification"
    t.index ["job_id"], name: "index_discovered_jobs_on_job_id"
    t.index ["job_source_id"], name: "index_discovered_jobs_on_job_source_id"
    t.index ["search_run_id"], name: "index_discovered_jobs_on_search_run_id"
    t.index ["source_scan_id", "fingerprint"], name: "index_discovered_jobs_on_source_scan_id_and_fingerprint", unique: true
    t.index ["source_scan_id"], name: "index_discovered_jobs_on_source_scan_id"
  end

  create_table "job_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "eligibility_flags", default: [], null: false, array: true
    t.datetime "first_seen_at", null: false
    t.bigint "job_id", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "last_validated_at", null: false
    t.integer "match_strength", default: 0, null: false
    t.jsonb "raw_decision", default: {}, null: false
    t.text "reason", default: "", null: false
    t.integer "score", default: 0, null: false
    t.bigint "search_profile_id", null: false
    t.string "seniority", default: "senior", null: false
    t.text "stack_tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.integer "user_state", default: 0, null: false
    t.index ["job_id"], name: "index_job_matches_on_job_id"
    t.index ["last_seen_at"], name: "index_job_matches_on_last_seen_at"
    t.index ["match_strength", "user_state"], name: "index_job_matches_on_match_strength_and_user_state"
    t.index ["search_profile_id", "job_id"], name: "index_job_matches_on_search_profile_id_and_job_id", unique: true
    t.index ["search_profile_id"], name: "index_job_matches_on_search_profile_id"
  end

  create_table "job_sources", force: :cascade do |t|
    t.string "adapter_key", default: "manual_only", null: false
    t.string "base_url"
    t.boolean "codex_fallback_enabled", default: false, null: false
    t.text "codex_fallback_reason"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "host", null: false
    t.datetime "last_codex_checked_at"
    t.datetime "last_codex_fallback_at"
    t.datetime "last_full_scan_at"
    t.string "name", null: false
    t.integer "priority", default: 100, null: false
    t.integer "scan_window_days", default: 20, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.integer "source_kind", default: 0, null: false
    t.boolean "supports_backfill", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["adapter_key"], name: "index_job_sources_on_adapter_key"
    t.index ["codex_fallback_enabled"], name: "index_job_sources_on_codex_fallback_enabled"
    t.index ["enabled"], name: "index_job_sources_on_enabled"
    t.index ["host"], name: "index_job_sources_on_host"
    t.index ["last_codex_checked_at"], name: "index_job_sources_on_last_codex_checked_at"
    t.index ["last_codex_fallback_at"], name: "index_job_sources_on_last_codex_fallback_at"
    t.index ["slug"], name: "index_job_sources_on_slug", unique: true
    t.index ["supports_backfill"], name: "index_job_sources_on_supports_backfill"
  end

  create_table "jobs", force: :cascade do |t|
    t.string "apply_url", null: false
    t.string "ats_name"
    t.string "canonical_url", null: false
    t.string "company_name", null: false
    t.datetime "created_at", null: false
    t.string "external_job_id"
    t.string "fingerprint", null: false
    t.datetime "first_seen_at", null: false
    t.bigint "job_source_id", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "last_validated_at", null: false
    t.integer "lifecycle_state", default: 0, null: false
    t.string "location_text"
    t.string "posted_text"
    t.datetime "published_at"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "remote_text"
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_url"], name: "index_jobs_on_canonical_url", unique: true
    t.index ["external_job_id"], name: "index_jobs_on_external_job_id"
    t.index ["fingerprint"], name: "index_jobs_on_fingerprint", unique: true
    t.index ["job_source_id"], name: "index_jobs_on_job_source_id"
    t.index ["last_seen_at"], name: "index_jobs_on_last_seen_at"
  end

  create_table "search_profiles", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "include_women_only", default: false, null: false
    t.integer "language_scope", default: 0, null: false
    t.text "location_terms", default: [], null: false, array: true
    t.string "name", null: false
    t.text "negative_terms", default: [], null: false, array: true
    t.boolean "required_remote", default: true, null: false
    t.integer "scan_window_days", default: 20, null: false
    t.text "seniority_terms", default: [], null: false, array: true
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.text "target_stacks", default: [], null: false, array: true
    t.text "target_titles", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["active"], name: "index_search_profiles_on_active"
    t.index ["language_scope"], name: "index_search_profiles_on_language_scope"
    t.index ["user_id", "slug"], name: "index_search_profiles_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_search_profiles_on_user_id"
  end

  create_table "search_run_items", force: :cascade do |t|
    t.string "apply_url"
    t.string "canonical_url"
    t.string "company_name"
    t.datetime "created_at", null: false
    t.bigint "job_id"
    t.integer "outcome", default: 0, null: false
    t.jsonb "payload", default: {}, null: false
    t.text "reason", default: "", null: false
    t.bigint "search_run_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_search_run_items_on_job_id"
    t.index ["outcome"], name: "index_search_run_items_on_outcome"
    t.index ["search_run_id"], name: "index_search_run_items_on_search_run_id"
  end

  create_table "search_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "expired_count", default: 0, null: false
    t.datetime "finished_at"
    t.integer "imported_count", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.integer "trigger_source", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "updated_count", default: 0, null: false
    t.string "window_label", default: "24h", null: false
    t.index ["started_at"], name: "index_search_runs_on_started_at"
    t.index ["status"], name: "index_search_runs_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "source_scans", force: :cascade do |t|
    t.integer "accepted_count", default: 0, null: false
    t.integer "borderline_count", default: 0, null: false
    t.integer "candidates_seen", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "cursor"
    t.text "error_message"
    t.integer "expired_count", default: 0, null: false
    t.datetime "finished_at"
    t.bigint "job_source_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "pages_scanned", default: 0, null: false
    t.integer "rejected_count", default: 0, null: false
    t.bigint "search_run_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["job_source_id"], name: "index_source_scans_on_job_source_id"
    t.index ["search_run_id", "job_source_id"], name: "index_source_scans_on_search_run_id_and_job_source_id", unique: true
    t.index ["search_run_id"], name: "index_source_scans_on_search_run_id"
    t.index ["status"], name: "index_source_scans_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "discovered_jobs", "job_sources"
  add_foreign_key "discovered_jobs", "jobs"
  add_foreign_key "discovered_jobs", "search_runs"
  add_foreign_key "discovered_jobs", "source_scans"
  add_foreign_key "job_matches", "jobs"
  add_foreign_key "job_matches", "search_profiles"
  add_foreign_key "jobs", "job_sources"
  add_foreign_key "search_profiles", "users"
  add_foreign_key "search_run_items", "jobs"
  add_foreign_key "search_run_items", "search_runs"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "source_scans", "job_sources"
  add_foreign_key "source_scans", "search_runs"
end
