class SourcesController < ApplicationController
  before_action :set_source, only: %i[edit update]

  def index
    @sources = JobSource.order(priority: :asc, name: :asc)
    @jobs_count_by_source_id = Job.group(:job_source_id).count
    @latest_scan_by_source_id = latest_scans.index_by(&:job_source_id)
  end

  def edit
    @settings_json = pretty_settings(@source.settings)
    prepare_adapter_options
  end

  def update
    @source.assign_attributes(source_params.except(:settings_json))
    @settings_json = source_params[:settings_json].to_s
    prepare_adapter_options

    parsed_settings = parse_settings_json(@settings_json)
    return render :edit, status: :unprocessable_entity if parsed_settings == :invalid

    @source.settings = parsed_settings

    if @source.save
      redirect_to sources_path, notice: "Fonte atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_source
      @source = JobSource.find(params[:id])
    end

    def source_params
      params.require(:job_source).permit(
        :name,
        :base_url,
        :host,
        :priority,
        :scan_window_days,
        :adapter_key,
        :enabled,
        :supports_backfill,
        :settings_json
      )
    end

    def parse_settings_json(raw_json)
      raw_json = raw_json.to_s
      return {} if raw_json.blank?

      parsed = JSON.parse(raw_json)
      return parsed if parsed.is_a?(Hash)

      @source.errors.add(:settings, "deve ser um objeto JSON")
      :invalid
    rescue JSON::ParserError
      @source.errors.add(:settings, "contém JSON inválido")
      :invalid
    end

    def pretty_settings(settings)
      JSON.pretty_generate(settings.presence || {})
    end

    def prepare_adapter_options
      supported_keys = JobDiscovery::Registry.supported_adapter_keys
      available_keys = [ "manual_only", *supported_keys ]
      current_key = @source.adapter_key.to_s

      if current_key.present? && !available_keys.include?(current_key)
        available_keys.unshift(current_key)
        @legacy_adapter_key = current_key
      else
        @legacy_adapter_key = nil
      end

      @adapter_options = available_keys.uniq.map do |key|
        [ adapter_label(key), key ]
      end
    end

    def adapter_label(key)
      return "#{key} (legado fora do catalogo)" if key == @legacy_adapter_key
      return "manual_only (sem backfill nativo)" if key == "manual_only"

      key
    end

    def latest_scans
      latest_scan_ids = SourceScan.select("DISTINCT ON (job_source_id) id")
                                  .order(:job_source_id, created_at: :desc, id: :desc)

      SourceScan.includes(:search_run).where(id: latest_scan_ids)
    end
end
