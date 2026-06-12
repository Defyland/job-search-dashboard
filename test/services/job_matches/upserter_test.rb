require "test_helper"

module JobMatches
  class UpserterTest < ActiveSupport::TestCase
    test "creates a new match from the policy decision" do
      job = jobs(:ruby_role)
      profile = search_profiles(:women_inclusive)
      timestamp = Time.zone.parse("2026-06-12 09:30:00")

      match = Upserter.call(job:, decision: decision_for(profile), timestamp:)

      assert_predicate match, :persisted?
      assert_equal job, match.job
      assert_equal profile, match.search_profile
      assert_equal "strong", match.match_strength
      assert_equal [ "ruby" ], match.stack_tags
      assert_equal [ "women_only" ], match.eligibility_flags
      assert_equal "new_match", match.user_state
      assert_equal timestamp, match.first_seen_at
      assert_equal timestamp, match.last_seen_at
      assert_equal timestamp, match.last_validated_at
      assert_equal(
        {
          "classification" => "strong",
          "remote_signal" => "Remote Brazil",
          "exclusion_reason" => nil
        },
        match.raw_decision
      )
    end

    test "updates the existing match without overwriting manual user state" do
      match = job_matches(:ruby_default)
      profile = match.search_profile
      match.update!(
        user_state: :applied,
        score: 65,
        reason: "estado anterior",
        last_seen_at: 3.days.ago,
        last_validated_at: 3.days.ago
      )
      timestamp = Time.zone.parse("2026-06-12 10:15:00")

      updated_match = Upserter.call(job: match.job, decision: decision_for(profile, score: 97, reason: "match atualizado"), timestamp:)

      assert_equal match.id, updated_match.id
      assert_equal "applied", updated_match.user_state
      assert_equal 97, updated_match.score
      assert_equal "match atualizado", updated_match.reason
      assert_equal timestamp, updated_match.last_seen_at
      assert_equal timestamp, updated_match.last_validated_at
    end

    private
      def decision_for(profile, score: 92, reason: "match forte")
        JobDiscovery::Policy::Result.new(
          classification: :strong,
          reason:,
          stack_tags: [ "ruby" ],
          score:,
          seniority: "senior",
          remote_signal: "Remote Brazil",
          exclusion_reason: nil,
          search_profile: profile,
          eligibility_flags: [ "women_only" ]
        )
      end
  end
end
