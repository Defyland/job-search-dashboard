class Api::V1::JobIngestionsController < Api::V1::BaseController
  def create
    result = JobIngestions::Importer.new(payload: ingestion_payload).call

    if result.success?
      render json: { search_run_id: result.search_run.id, summary: result.summary }, status: :created
    else
      render json: { error: "invalid_ingestion_payload", details: result.errors }, status: :unprocessable_entity
    end
  end

  private
    def ingestion_payload
      params.except(:controller, :action).to_unsafe_h
    end
end
