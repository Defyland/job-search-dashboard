class SourcesController < ApplicationController
  before_action :set_source, only: %i[edit update]

  def index
    @sources = JobSource.left_outer_joins(:jobs)
                        .select("job_sources.*, COUNT(jobs.id) AS jobs_count")
                        .group("job_sources.id")
                        .order(priority: :asc, name: :asc)
  end

  def edit
    @settings_json = pretty_settings(@source.settings)
  end

  def update
    @source.assign_attributes(source_params.except(:settings_json))
    @settings_json = source_params[:settings_json].to_s

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
end
