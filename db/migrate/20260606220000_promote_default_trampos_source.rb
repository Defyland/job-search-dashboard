class PromoteDefaultTramposSource < ActiveRecord::Migration[8.1]
  class MigrationJobSource < ApplicationRecord
    self.table_name = "job_sources"
  end

  def up
    MigrationJobSource.where(
      slug: "trampos",
      adapter_key: "manual_only",
      supports_backfill: false,
      base_url: "https://trampos.co",
      host: "trampos.co",
      priority: 30,
      enabled: true,
      scan_window_days: 20,
      settings: {}
    ).update_all(
      adapter_key: "trampos_opportunities_api",
      supports_backfill: true,
      updated_at: Time.current
    )
  end

  def down
    MigrationJobSource.where(
      slug: "trampos",
      adapter_key: "trampos_opportunities_api",
      supports_backfill: true,
      base_url: "https://trampos.co",
      host: "trampos.co",
      priority: 30,
      enabled: true,
      scan_window_days: 20,
      settings: {}
    ).update_all(
      adapter_key: "manual_only",
      supports_backfill: false,
      updated_at: Time.current
    )
  end
end
