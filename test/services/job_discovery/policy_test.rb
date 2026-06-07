require "test_helper"

class JobDiscovery::PolicyTest < ActiveSupport::TestCase
  test "classifies a strong senior react title" do
    result = JobDiscovery::Policy.new(search_profile: search_profiles(:default)).classify(
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
      result = JobDiscovery::Policy.new(search_profile: search_profiles(:default)).classify(
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

  test "accepts women only roles for profiles that include them" do
    result = JobDiscovery::Policy.new(search_profile: search_profiles(:women_inclusive)).classify(
      title: "Frontend Engineer Senior React",
      remote_text: "Remoto Brasil",
      location_text: "Brasil",
      description: "Vaga afirmativa para mulheres na engenharia",
      source_slug: "gupy",
      posted_text: "publicada hoje",
      published_at: nil
    )

    assert result.accepted?
    assert_includes result.eligibility_flags, "women_only"
  end

  test "matches java and dotnet from configurable profile stacks" do
    java_profile = users(:one).search_profiles.create!(
      name: "Senior Java e .NET",
      target_stacks: [ "java", ".net" ],
      target_titles: [ "backend", "software engineer" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remote", "brasil" ],
      negative_terms: [ "junior" ]
    )

    java_result = JobDiscovery::Policy.new(search_profile: java_profile).classify(
      title: "Senior Backend Engineer Java",
      remote_text: "Remote Brazil",
      location_text: "Brazil",
      description: "Spring Boot",
      source_slug: "lever",
      posted_text: "today",
      published_at: nil
    )
    dotnet_result = JobDiscovery::Policy.new(search_profile: java_profile).classify(
      title: "Senior Software Engineer C#",
      remote_text: "Remote Brazil",
      location_text: "Brazil",
      description: "ASP.NET",
      source_slug: "lever",
      posted_text: "today",
      published_at: nil
    )

    assert java_result.accepted?
    assert_includes java_result.stack_tags, "java"
    assert dotnet_result.accepted?
    assert_includes dotnet_result.stack_tags, ".net"
  end

  test "exposes fallback policy contract from canonical policy" do
    contract = JobDiscovery::Policy.contract(search_profile: search_profiles(:default))

    assert_includes contract.fetch(:stack_terms), "ruby on rails"
    assert_includes contract.fetch(:exclude_terms), "mulheres"
    assert_equal "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions", contract.fetch(:output)
  end

  test "rejects non remote roles" do
    result = JobDiscovery::Policy.new(search_profile: search_profiles(:default)).classify(
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
