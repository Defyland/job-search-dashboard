require "test_helper"

class SearchProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "lists search profiles" do
    get search_profiles_path

    assert_response :success
    assert_match "Senior Ruby/Rails/React", response.body
  end

  test "creates java profile from simple terms" do
    assert_difference("SearchProfile.count", 1) do
      post search_profiles_path,
           params: {
             search_profile: {
               name: "Senior Java Remote",
               target_stacks_text: "java, spring",
               target_titles_text: "backend, software engineer",
               seniority_terms_text: "senior, staff",
               location_terms_text: "remote, brasil",
               negative_terms_text: "junior, pleno",
               required_remote: "1",
               include_women_only: "0",
               language_scope: "portuguese",
               active: "1",
               scan_window_days: 20
             }
           }
    end

    profile = SearchProfile.order(:created_at).last
    assert_redirected_to jobs_path(search_profile_id: profile.id)
    assert_equal [ "java", "spring" ], profile.target_stacks
    assert profile.language_scope_portuguese?
  end

  test "updates women only preference" do
    patch search_profile_path(search_profiles(:default)),
          params: {
            search_profile: {
              include_women_only: "1",
              target_stacks_text: search_profiles(:default).target_stacks_text,
              target_titles_text: search_profiles(:default).target_titles_text,
              seniority_terms_text: search_profiles(:default).seniority_terms_text,
              location_terms_text: search_profiles(:default).location_terms_text,
              negative_terms_text: search_profiles(:default).negative_terms_text
            }
          }

    assert_redirected_to search_profiles_path
    assert search_profiles(:default).reload.include_women_only?
  end
end
