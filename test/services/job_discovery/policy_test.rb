require "test_helper"

class JobDiscovery::PolicyTest < ActiveSupport::TestCase
  test "classifies a strong senior react title" do
    result = JobDiscovery::Policy.new.classify(
      title: "Frontend Engineer Senior React",
      remote_text: "Remoto Brasil",
      location_text: "Brasil",
      description: "Equipe frontend com React",
      source_slug: "gupy",
      posted_text: "publicada hoje",
      published_at: Time.zone.parse("2026-06-06 10:00:00")
    )

    assert result.accepted?
    assert_equal :strong, result.classification
    assert_includes result.stack_tags, "react"
  end

  test "rejects women only roles" do
    [
      "Vaga afirmativa para mulheres na engenharia",
      "Oportunidade exclusiva para mulheres",
      "Oportunidade exclusivo para mulheres",
      "Banco de talentos mulheres desenvolvedoras",
      "Women only role for React engineers"
    ].each do |description|
      result = JobDiscovery::Policy.new.classify(
        title: "Frontend Engineer Senior React",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        description:,
        source_slug: "gupy",
        posted_text: "publicada hoje",
        published_at: nil
      )

      assert_equal :rejected, result.classification, description
      assert_match(/mulheres/, result.reason)
    end
  end

  test "exposes fallback policy contract from canonical policy" do
    contract = JobDiscovery::Policy.contract

    assert_includes contract.fetch(:stack_terms), "ruby on rails"
    assert_includes contract.fetch(:exclude_terms), "mulheres"
    assert_equal "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions", contract.fetch(:output)
  end

  test "rejects non remote roles" do
    result = JobDiscovery::Policy.new.classify(
      title: "Senior Ruby on Rails Engineer",
      remote_text: "São Paulo - SP e Híbrido",
      location_text: "São Paulo - SP",
      description: "Atuação híbrida",
      source_slug: "gupy",
      posted_text: "sem data publica",
      published_at: nil
    )

    assert_equal :rejected, result.classification
    assert_match(/remoto/i, result.reason)
  end
end
