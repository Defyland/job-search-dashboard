module JobMatches
  class Upserter
    def self.call(job:, decision:, timestamp: Time.current)
      new(job:, decision:, timestamp:).call
    end

    def initialize(job:, decision:, timestamp: Time.current)
      @job = job
      @decision = decision
      @timestamp = timestamp
    end

    def call
      match = @job.job_matches.find_or_initialize_by(search_profile: @decision.search_profile)
      assign_attributes(match)

      JobMatch.transaction(requires_new: true) do
        match.save!
      end

      match
    rescue ActiveRecord::RecordNotUnique
      recover_match
    rescue ActiveRecord::RecordInvalid => error
      raise unless unique_job_match_conflict?(error.record)

      recover_match
    end

    private
      def assign_attributes(match)
        match.assign_attributes(
          match_strength: JobMatch.match_strengths.fetch(@decision.classification.to_s),
          score: @decision.score,
          reason: @decision.reason,
          seniority: @decision.seniority,
          stack_tags: @decision.stack_tags,
          eligibility_flags: @decision.eligibility_flags,
          raw_decision: {
            classification: @decision.classification,
            remote_signal: @decision.remote_signal,
            exclusion_reason: @decision.exclusion_reason
          },
          last_seen_at: @timestamp,
          last_validated_at: @timestamp
        )
        match.first_seen_at ||= @timestamp
        match.user_state = :new_match if match.new_record?
      end

      def recover_match
        match = @job.job_matches.reset.find_by!(search_profile: @decision.search_profile)
        assign_attributes(match)
        match.save!
        match
      end

      def unique_job_match_conflict?(record)
        record.is_a?(JobMatch) &&
          (record.errors.of_kind?(:job_id, :taken) || record.errors.of_kind?(:search_profile_id, :taken))
      end
  end
end
