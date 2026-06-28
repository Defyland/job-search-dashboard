require "test_helper"

module Jobs
  class DetailSnapshotTest < ActiveSupport::TestCase
    test "extracts sanitized description sections from job payload" do
      job = jobs(:react_role)
      job.update!(
        raw_payload: {
          description: <<~HTML
            <h2>Responsabilidades:</h2>
            <p>Desenvolver produtos React.</p>
            <script>alert("x")</script>
            <h2>Requisitos:</h2>
            <p>Experiencia com TypeScript.</p>
            <h2>Beneficios:</h2>
            <p>Trabalho remoto.</p>
          HTML
        }
      )

      snapshot = DetailSnapshot.new(
        job:,
        job_match: job_matches(:react_default),
        search_profile: search_profiles(:default)
      )

      assert snapshot.description_available?
      assert_includes snapshot.description_text, "Desenvolver produtos React."
      assert_no_match "<script>", snapshot.description_text
      assert_no_match "alert", snapshot.description_text
      assert_includes snapshot.responsibilities, "Desenvolver produtos React."
      assert_includes snapshot.requirements, "Experiencia com TypeScript."
      assert_includes snapshot.benefits, "Trabalho remoto."
    end

    test "falls back to local metadata when description is missing" do
      job = jobs(:react_role)
      job.update!(raw_payload: { title: job.title })

      snapshot = DetailSnapshot.new(
        job:,
        job_match: job_matches(:react_default),
        search_profile: search_profiles(:default)
      )

      refute snapshot.description_available?
      assert_includes snapshot.description_text, job.title
      assert_includes snapshot.attention_points, "Descricao completa nao foi capturada; use o link original para confirmar requisitos."
    end
  end
end
