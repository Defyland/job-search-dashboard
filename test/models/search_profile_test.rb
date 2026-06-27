require "test_helper"

class SearchProfileTest < ActiveSupport::TestCase
  test "normalizes configurable terms" do
    profile = users(:one).search_profiles.create!(
      name: " Java Senior ",
      target_stacks: [ " Java ", "java", "Spring, Kotlin" ],
      target_titles: [ "Backend" ],
      seniority_terms: [ "Senior" ],
      location_terms: [ "Remote" ],
      negative_terms: [ "Junior" ]
    )

    assert_equal "java-senior", profile.slug
    assert_equal [ "java", "spring", "kotlin" ], profile.target_stacks
    assert profile.language_scope_both?
  end

  test "deduplicates generated slugs for the same user" do
    users(:one).search_profiles.create!(name: "Senior Java Remote", target_stacks: [ "java" ])

    duplicate = users(:one).search_profiles.create!(name: "Senior Java Remote", target_stacks: [ "java" ])

    assert_equal "Senior Java Remote 2", duplicate.name
    assert_equal "senior-java-remote-2", duplicate.slug
  end

  test "women only terms are profile scoped" do
    default_profile = search_profiles(:default)
    inclusive_profile = search_profiles(:women_inclusive)

    assert_includes default_profile.effective_exclude_terms, "women only"
    assert_not_includes inclusive_profile.effective_exclude_terms, "women only"
  end

  test "policy contract exposes title language scope" do
    profile = search_profiles(:default)

    assert_equal "both", profile.policy_contract.fetch(:language_scope)
    assert_equal "Português e Inglês", profile.language_scope_label
  end
end
