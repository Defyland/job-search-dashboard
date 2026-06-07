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

  test "portuguese salesforce profile accepts portuguese titles and rejects english titles" do
    profile = salesforce_profile(language_scope: :portuguese)

    accepted = classify_salesforce(profile, title: "Desenvolvedor Salesforce Sênior", remote_text: "Remoto Brasil", location_text: "Brasil")
    rejected = classify_salesforce(profile, title: "Senior Salesforce Developer", remote_text: "Remote Brazil", location_text: "Brazil")
    ambiguous_english = classify_salesforce(profile, title: "Senior Salesforce Administrator", remote_text: "Remote Brazil", location_text: "Brazil")

    assert accepted.accepted?
    assert_includes accepted.stack_tags, "salesforce"
    assert_equal :rejected, rejected.classification
    assert_match(/idioma/, rejected.reason)
    assert_equal :rejected, ambiguous_english.classification
    assert_match(/idioma/, ambiguous_english.reason)
    assert_not JobDiscovery::Policy.new(search_profile: profile).potential_match?("Senior Salesforce Administrator")
  end

  test "english salesforce profile accepts english titles and rejects portuguese titles" do
    profile = salesforce_profile(language_scope: :english)

    accepted = classify_salesforce(profile, title: "Senior Salesforce Developer", remote_text: "Remote Brazil", location_text: "Brazil")
    rejected = classify_salesforce(profile, title: "Desenvolvedor Salesforce Sênior", remote_text: "Remoto Brasil", location_text: "Brasil")
    ambiguous_portuguese = classify_salesforce(profile, title: "Analista Salesforce Sênior", remote_text: "Remoto Brasil", location_text: "Brasil")

    assert accepted.accepted?
    assert_includes accepted.stack_tags, "salesforce"
    assert_equal :rejected, rejected.classification
    assert_match(/idioma/, rejected.reason)
    assert_equal :rejected, ambiguous_portuguese.classification
    assert_match(/idioma/, ambiguous_portuguese.reason)
    assert_not JobDiscovery::Policy.new(search_profile: profile).potential_match?("Analista Salesforce Sênior")
  end

  test "bilingual salesforce profile accepts portuguese and english titles" do
    profile = salesforce_profile(language_scope: :both)

    portuguese = classify_salesforce(profile, title: "Engenheiro Salesforce Sênior", remote_text: "Remoto Brasil", location_text: "Brasil")
    english = classify_salesforce(profile, title: "Senior Salesforce Engineer", remote_text: "Remote Brazil", location_text: "Brazil")

    assert portuguese.accepted?
    assert english.accepted?
    assert_includes portuguese.stack_tags, "salesforce"
    assert_includes english.stack_tags, "salesforce"
  end

  test "exposes fallback policy contract from canonical policy" do
    contract = JobDiscovery::Policy.contract(search_profile: search_profiles(:default))

    assert_includes contract.fetch(:stack_terms), "ruby on rails"
    assert_includes contract.fetch(:exclude_terms), "mulheres"
    assert_equal "both", contract.fetch(:language_scope)
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

  private
    def salesforce_profile(language_scope:)
      users(:one).search_profiles.create!(
        name: "Senior Salesforce #{language_scope}",
        target_stacks_text: "salesforce",
        target_titles_text: "salesforce, software engineer, developer, consultant, engenheiro, desenvolvedor, consultor",
        seniority_terms_text: "senior, sênior, sr",
        location_terms_text: "remote, remoto, brazil, brasil, latam",
        negative_terms_text: "junior, pleno, internship",
        required_remote: true,
        include_women_only: false,
        language_scope:,
        scan_window_days: 20,
        active: true
      )
    end

    def classify_salesforce(profile, title:, remote_text:, location_text:)
      JobDiscovery::Policy.new(search_profile: profile).classify(
        title:,
        remote_text:,
        location_text:,
        description: "Salesforce Apex Lightning integrations",
        source_slug: "manual",
        posted_text: "publicada hoje",
        published_at: nil
      )
    end
end
