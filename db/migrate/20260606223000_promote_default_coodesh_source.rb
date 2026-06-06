class PromoteDefaultCoodeshSource < ActiveRecord::Migration[8.1]
  class MigrationJobSource < ApplicationRecord
    self.table_name = "job_sources"
  end

  def up
    MigrationJobSource.where(
      slug: "coodesh",
      adapter_key: "manual_only",
      supports_backfill: false,
      base_url: "https://coodesh.com",
      host: "coodesh.com",
      priority: 30,
      enabled: true,
      scan_window_days: 20,
      settings: {}
    ).update_all(
      adapter_key: "coodesh_jobs_sitemap",
      supports_backfill: true,
      updated_at: Time.current
    )
  end

  def down
    MigrationJobSource.where(
      slug: "coodesh",
      adapter_key: "coodesh_jobs_sitemap",
      supports_backfill: true,
      base_url: "https://coodesh.com",
      host: "coodesh.com",
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
