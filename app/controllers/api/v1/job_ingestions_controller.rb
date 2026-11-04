class Api::V1::JobIngestionsController < Api::V1::BaseController
  def create
    result = JobIngestions::Importer.new(payload: ingestion_payload).call

    if result.conflict
      render json: { error: "client_run_id_conflict", details: result.errors }, status: :conflict
    elsif result.success?
      render json: { search_run_id: result.search_run.id, summary: result.summary, replayed: result.replayed },
             status: result.replayed ? :ok : :created
    else
      render json: { error: "invalid_ingestion_payload", details: result.errors }, status: :unprocessable_entity
    end
  end

  private
    def ingestion_payload
      params.except(:controller, :action).to_unsafe_h
    end
end
