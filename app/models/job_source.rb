class JobSource < ApplicationRecord
  DEFAULT_CATALOG = [
    {
      name: "Gupy",
      slug: "gupy",
      source_kind: :ats,
      base_url: "https://gupy.io",
      host: "gupy.io",
      priority: 10,
      adapter_key: "gupy_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        board_urls: [
          "https://clicksign.gupy.io/",
          "https://memed.gupy.io/"
        ]
      }
    },
    { name: "Sólides", slug: "solides", source_kind: :ats, base_url: "https://vagas.solides.com.br", host: "vagas.solides.com.br", priority: 20, adapter_key: "solides_portal_vacancies", supports_backfill: true, scan_window_days: 20 },
    {
      name: "Recrutei",
      slug: "recrutei",
      source_kind: :ats,
      base_url: "https://jobs.recrutei.com.br",
      host: "jobs.recrutei.com.br",
      priority: 20,
      adapter_key: "recrutei_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        company_labels: [ "maxxi" ],
        vacancy_urls: [
          "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior"
        ]
      }
    },
    {
      name: "Inhire",
      slug: "inhire",
      source_kind: :ats,
      base_url: "https://inhire.app",
      host: "inhire.app",
      priority: 20,
      adapter_key: "inhire_career_pages",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        career_page_slugs: %w[yandeh deal mb lighthouseit matera dotgroup inco casacred]
      }
    },
    {
      name: "Lever",
      slug: "lever",
      source_kind: :ats,
      base_url: "https://jobs.lever.co",
      host: "jobs.lever.co",
      priority: 20,
      adapter_key: "lever_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        company_slugs: %w[ciandt jobgether decilegroup toptal]
      }
    },
    {
      name: "Greenhouse",
      slug: "greenhouse",
      source_kind: :ats,
      base_url: "https://job-boards.greenhouse.io",
      host: "job-boards.greenhouse.io",
      priority: 20,
      adapter_key: "greenhouse_boards_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        board_tokens: %w[rdsourcing fueledcareers]
      }
    },
    {
      name: "Ashby",
      slug: "ashby",
      source_kind: :ats,
      base_url: "https://jobs.ashbyhq.com",
      host: "jobs.ashbyhq.com",
      priority: 20,
      adapter_key: "ashby_job_board",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        board_slugs: %w[ruby-labs skydropx]
      }
    },
    { name: "Teamtailor", slug: "teamtailor", source_kind: :ats, base_url: "https://career.teamtailor.com", host: "teamtailor.com", priority: 20, adapter_key: "teamtailor_company_boards", supports_backfill: true, scan_window_days: 20 },
    { name: "Workable", slug: "workable", source_kind: :ats, base_url: "https://jobs.workable.com", host: "jobs.workable.com", priority: 20, adapter_key: "workable_global_api", supports_backfill: true, scan_window_days: 20 },
    {
      name: "SmartRecruiters",
      slug: "smartrecruiters",
      source_kind: :ats,
      base_url: "https://jobs.smartrecruiters.com",
      host: "smartrecruiters.com",
      priority: 20,
      adapter_key: "smartrecruiters_postings_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        company_identifiers: [ "smartrecruiters" ]
      }
    },
    { name: "Remotar", slug: "remotar", source_kind: :platform, base_url: "https://remotar.com.br", host: "remotar.com.br", priority: 30, adapter_key: "remotar_jobs_api", supports_backfill: true, scan_window_days: 20 },
    { name: "ProgramaThor", slug: "programathor", source_kind: :platform, base_url: "https://programathor.com.br", host: "programathor.com.br", priority: 30, adapter_key: "programathor_remote_senior", supports_backfill: true, scan_window_days: 20 },
    { name: "Coodesh", slug: "coodesh", source_kind: :platform, base_url: "https://coodesh.com", host: "coodesh.com", priority: 30, adapter_key: "manual_only", supports_backfill: false, scan_window_days: 20 },
    { name: "Trampos", slug: "trampos", source_kind: :platform, base_url: "https://trampos.co", host: "trampos.co", priority: 30, adapter_key: "manual_only", supports_backfill: false, scan_window_days: 20 },
    { name: "APInfo", slug: "apinfo", source_kind: :platform, base_url: "https://apinfo.com", host: "apinfo.com", priority: 40, adapter_key: "manual_only", supports_backfill: false, scan_window_days: 20 },
    { name: "RubyOnRemote", slug: "rubyonremote", source_kind: :platform, base_url: "https://rubyonremote.com", host: "rubyonremote.com", priority: 40, adapter_key: "manual_only", supports_backfill: false, scan_window_days: 20 }
  ].freeze

  enum :source_kind, { ats: 0, platform: 1, company: 2, aggregator: 3 }, prefix: true

  has_many :jobs, dependent: :restrict_with_exception
  has_many :source_scans, dependent: :restrict_with_exception
  has_many :discovered_jobs, dependent: :restrict_with_exception

  validates :name, :slug, :host, presence: true
  validates :slug, uniqueness: true
  validates :priority, numericality: { greater_than_or_equal_to: 0 }
  validates :scan_window_days, numericality: { greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }
  scope :backfillable, -> { enabled.where(supports_backfill: true) }

  before_validation :normalize_fields

  def self.seed_defaults!
    DEFAULT_CATALOG.each do |attributes|
      source = find_or_initialize_by(slug: attributes.fetch(:slug))
      if source.new_record?
        source.assign_attributes(attributes)
      else
        apply_catalog_defaults!(source, attributes)
      end
      source.save!
    end
  end

  def self.resolve_for_ingestion(name:, slug:, host:)
    normalized_slug = slug.to_s.parameterize
    normalized_name = normalize_lookup_key(name)
    normalized_host = host.to_s.downcase.sub(/\Awww\./, "")

    all.sort_by { |source| [ -source.host.to_s.length, source.priority, source.name ] }.find do |source|
      source.slug == normalized_slug ||
        (normalized_name.present? && normalize_lookup_key(source.name) == normalized_name) ||
        host_matches?(normalized_host, source.host)
    end
  end

  private
    def self.apply_catalog_defaults!(source, attributes)
      attributes.each do |key, value|
        if key.to_sym == :settings
          source.settings = default_settings(value).deep_merge(source.settings || {})
          next
        end

        source.public_send("#{key}=", value) if source.public_send(key).nil?
      end
    end

    def self.default_settings(value)
      value.to_h.deep_stringify_keys
    end

    def self.normalize_lookup_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    def self.host_matches?(candidate_host, existing_host)
      return false if candidate_host.blank? || existing_host.blank?

      candidate_host == existing_host ||
        candidate_host.end_with?(".#{existing_host}") ||
        existing_host.end_with?(".#{candidate_host}")
    end

    def normalize_fields
      self.name = name.to_s.strip
      self.base_url = normalize_url(base_url)
      self.host = normalized_host.presence
      self.slug = slug.presence || name.presence || host
      self.slug = slug.to_s.parameterize
      self.priority ||= 100
      self.adapter_key = adapter_key.presence || "manual_only"
      self.enabled = true if enabled.nil?
      self.supports_backfill = false if supports_backfill.nil?
      self.scan_window_days ||= 20
      self.settings ||= {}
    end

    def normalized_host
      raw_host = host.presence || extract_host(base_url)
      raw_host.to_s.downcase.sub(/\Awww\./, "")
    end

    def extract_host(url)
      URI.parse(url).host
    rescue URI::InvalidURIError, NoMethodError
      nil
    end

    def normalize_url(url)
      return if url.blank?

      url.to_s.strip.delete_suffix("/")
    end
end
