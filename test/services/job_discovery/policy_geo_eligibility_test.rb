require "test_helper"

class JobDiscovery::PolicyGeoEligibilityTest < ActiveSupport::TestCase
  def classify(remote_text:, location_text:, description: "Build Rails services with Ruby and Rails.", profile: search_profiles(:default))
    JobDiscovery::Policy.new(search_profile: profile).classify(
      title: "Senior Ruby on Rails Engineer",
      remote_text:,
      location_text:,
      description:,
      source_slug: "hirerubydevs",
      posted_text: "publicada hoje",
      published_at: Time.current
    )
  end

  test "rejects remote roles restricted to a region that excludes Brazil and LatAm" do
    [
      [ "Remote (US only)", "United States" ],
      [ "Remote", "Must be authorized to work in the United States" ],
      [ "Remote - Europe only", "Europe" ],
      [ "Fully remote", "Candidates must be based in the United Kingdom" ],
      [ "Remote, USA", "This role is open to US-based candidates only" ],
      [ "Remote", "Open to Canada only" ],
      [ "Remote", "US citizens preferred for this position" ],
      [ "Remote", "Applicants must reside within the EU" ]
    ].each do |remote_text, location_text|
      result = classify(remote_text:, location_text:)

      assert_not result.accepted?, "expected #{location_text.inspect} to be rejected"
      assert_match(/vaga restrita a outra regiao/, result.reason)
    end
  end

  test "keeps the matched restriction phrase in the reason so the call is auditable" do
    result = classify(remote_text: "Remote (US only)", location_text: "United States")

    assert_equal "vaga restrita a outra regiao: US only", result.reason
    assert_equal result.reason, result.exclusion_reason
  end

  test "accepts roles open worldwide even when they name a foreign country" do
    [
      [ "Remote - Worldwide", "Anywhere" ],
      [ "Remote worldwide", "United States (HQ)" ],
      [ "Fully remote, global team", "Berlin, Germany" ]
    ].each do |remote_text, location_text|
      result = classify(remote_text:, location_text:)

      assert result.accepted?, "expected #{location_text.inspect} to stay accepted"
    end
  end

  test "accepts roles that include the candidate's own region alongside foreign ones" do
    [
      [ "Remote", "Brazil, United States" ],
      [ "Remoto", "Brasil" ],
      [ "Remote", "LATAM" ],
      [ "Remote", "Open to candidates in Latin America and Canada" ]
    ].each do |remote_text, location_text|
      result = classify(remote_text:, location_text:)

      assert result.accepted?, "expected #{location_text.inspect} to stay accepted"
    end
  end

  test "a plain remote role with no geographic restriction is unaffected" do
    result = classify(remote_text: "Remote", location_text: "Remote")

    assert result.accepted?
    assert_equal :strong, result.classification
  end

  test "merely naming a foreign country is not a restriction" do
    result = classify(
      remote_text: "Remote",
      location_text: "United States",
      description: "Build Rails services. Our headquarters are in New York and the team is distributed."
    )

    assert result.accepted?, "an unqualified country mention must not reject the role"
  end

  test "a profile scoped to global remote is not filtered by foreign restrictions" do
    profile = search_profiles(:default)
    profile.update!(location_terms: [ "remote", "worldwide", "global", "anywhere" ])

    result = classify(remote_text: "Remote (US only)", location_text: "United States", profile:)

    assert result.accepted?, "a global-remote profile has no region to be excluded from"
  end

  test "a profile that does not require remote is not filtered by foreign restrictions" do
    profile = search_profiles(:default)
    profile.update!(required_remote: false)

    result = classify(remote_text: "Remote (US only)", location_text: "United States", profile:)

    assert result.accepted?
  end

  # Regression: "us" was matched case-insensitively, so the English pronoun in
  # "contact us", "join us" and "work with us" was read as the United States and
  # rejected healthy postings. Acronyms are now matched as written.
  test "does not treat the English pronoun 'us' as the United States" do
    [
      "Reach out to us only if you have Rails experience",
      "Work with us - only remote",
      "This role is only for people who love Ruby, join us",
      "Only senior engineers; write us a short intro"
    ].each do |location_text|
      result = classify(remote_text: "Remote", location_text:)

      assert result.accepted?, "the pronoun in #{location_text.inspect} must not read as a US restriction"
    end
  end

  test "still blocks the written acronyms it is meant to catch" do
    {
      "US only" => "US only",
      "EU residents only" => "EU residents",
      "UK based only" => "UK based",
      "Applicants must reside within the EU" => "must reside within the EU"
    }.each do |location_text, expected_phrase|
      result = classify(remote_text: "Remote", location_text:)

      assert_not result.accepted?, "#{location_text.inspect} must be rejected"
      assert_equal "vaga restrita a outra regiao: #{expected_phrase}", result.reason
    end
  end

  test "an unrestricted mention of a foreign region stays accepted" do
    [
      "We overlap with Europe timezones but hire globally",
      "Our India office supports the team"
    ].each do |location_text|
      result = classify(remote_text: "Remote", location_text:)

      assert result.accepted?, "#{location_text.inspect} names a region without restricting it"
    end
  end
end
