module SearchProfiles
  class Bootstrapper
    def initialize(search_profile:, job_scope: Job.active.includes(:job_source))
      @search_profile = search_profile
      @job_scope = job_scope
      @policy = JobDiscovery::Policy.new(search_profile: @search_profile)
    end

    def call
      @job_scope.find_each.sum do |job|
        decision = classify(job)
        next 0 unless decision.accepted?

        upsert_match(job, decision)
        1
      end
    end

    private
      def classify(job)
        @policy.classify(
          title: job.title,
          remote_text: job.remote_text,
          location_text: job.location_text,
          description: description_for(job),
          source_slug: job.job_source&.slug,
          posted_text: job.posted_text,
          published_at: job.published_at
        )
      end

      def description_for(job)
        payload = job.raw_payload.deep_stringify_keys

        [
          payload["description"],
          payload["body"],
          payload["requirements"],
          payload["summary"]
        ].compact.join(" ")
      end

      def upsert_match(job, decision)
        timestamp = Time.current
        match = job.job_matches.find_or_initialize_by(search_profile: @search_profile)
        assign_attributes(match, decision, timestamp)

        JobMatch.transaction(requires_new: true) do
          match.save!
        end
      rescue ActiveRecord::RecordNotUnique
        recover_match(job, decision, timestamp)
      rescue ActiveRecord::RecordInvalid => error
        raise unless unique_job_match_conflict?(error.record)

        recover_match(job, decision, timestamp)
      end

      def assign_attributes(match, decision, timestamp)
        match.assign_attributes(
          match_strength: JobMatch.match_strengths.fetch(decision.classification.to_s),
          score: decision.score,
          reason: decision.reason,
          seniority: decision.seniority,
          stack_tags: decision.stack_tags,
          eligibility_flags: decision.eligibility_flags,
          raw_decision: {
            classification: decision.classification,
            remote_signal: decision.remote_signal,
            exclusion_reason: decision.exclusion_reason
          },
          last_seen_at: timestamp,
          last_validated_at: timestamp
        )
        match.first_seen_at ||= timestamp
        match.user_state = :new_match if match.new_record?
      end

      def recover_match(job, decision, timestamp)
        match = job.job_matches.reset.find_by!(search_profile: @search_profile)
        assign_attributes(match, decision, timestamp)
        match.save!
      end

      def unique_job_match_conflict?(record)
        record.is_a?(JobMatch) &&
          (record.errors.of_kind?(:job_id, :taken) || record.errors.of_kind?(:search_profile_id, :taken))
      end
  end
end
