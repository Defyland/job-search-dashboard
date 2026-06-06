class Api::V1::BaseController < ActionController::API
  before_action :authenticate_ingestion!

  private
    def authenticate_ingestion!
      expected_token = ENV["INGEST_SHARED_TOKEN"].to_s

      if expected_token.blank?
        render json: { error: "ingest_token_not_configured" }, status: :service_unavailable
        return
      end

      provided_token = request.authorization.to_s.delete_prefix("Bearer ").strip

      valid_token = provided_token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)

      return if valid_token

      render json: { error: "invalid_ingest_token" }, status: :unauthorized
    end
end
