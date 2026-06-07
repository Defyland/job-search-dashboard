class AddCodexFallbackToJobSources < ActiveRecord::Migration[8.1]
  class MigrationJobSource < ApplicationRecord
    self.table_name = "job_sources"
  end

  def up
    add_column :job_sources, :codex_fallback_enabled, :boolean, null: false, default: false
    add_column :job_sources, :codex_fallback_reason, :text
    add_column :job_sources, :last_codex_fallback_at, :datetime
    add_index :job_sources, :codex_fallback_enabled
    add_index :job_sources, :last_codex_fallback_at

    MigrationJobSource.reset_column_information
    MigrationJobSource.where(slug: "apinfo", adapter_key: "manual_only", supports_backfill: false).update_all(
      codex_fallback_enabled: true,
      codex_fallback_reason: "Fonte publica rate-limited; usar Codex para descoberta assistida e ingestion API."
    )
    MigrationJobSource.where(slug: "rubyonremote", adapter_key: "manual_only", supports_backfill: false).update_all(
      codex_fallback_enabled: true,
      codex_fallback_reason: "Fonte protegida por Cloudflare para o worker Rails; usar Codex fallback quando houver busca assistida."
    )
  end

  def down
    remove_index :job_sources, :last_codex_fallback_at
    remove_index :job_sources, :codex_fallback_enabled
    remove_column :job_sources, :last_codex_fallback_at
    remove_column :job_sources, :codex_fallback_reason
    remove_column :job_sources, :codex_fallback_enabled
  end
end
