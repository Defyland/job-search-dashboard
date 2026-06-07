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
  end

  test "women only terms are profile scoped" do
    default_profile = search_profiles(:default)
    inclusive_profile = search_profiles(:women_inclusive)

    assert_includes default_profile.effective_exclude_terms, "women only"
    assert_not_includes inclusive_profile.effective_exclude_terms, "women only"
  end
end
