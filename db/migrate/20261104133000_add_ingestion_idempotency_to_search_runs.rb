class AddIngestionIdempotencyToSearchRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :search_runs, :client_run_id, :string
    add_column :search_runs, :request_digest, :string
    add_index :search_runs, :client_run_id,
              unique: true,
              where: "client_run_id IS NOT NULL",
              name: "index_search_runs_on_client_run_id"
  end
end
