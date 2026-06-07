module JobIngestions
  class Store
    attr_reader :summary

    def initialize(search_run:, source_resolver: JobSources::Resolver.new)
      @search_run = search_run
      @source_resolver = source_resolver
      @summary = {
        imported_count: 0,
        updated_count: 0,
        expired_count: 0,
        rejected_count: 0
      }
    end

    def reject(payload:, reason:)
      build_run_item(nil, :rejected, reason, payload)
      @summary[:rejected_count] += 1
    end

    def expire(existing_job:, reason:, payload:)
      if existing_job
        existing_job.update!(lifecycle_state: :expired, last_validated_at: Time.current)
        build_run_item(existing_job, :expired, reason, payload)
        @summary[:expired_count] += 1
      else
        reject(payload:, reason: "vaga expirada sem registro local")
      end
    end

    def resolve_source(attributes:, payload:)
      host = attributes[:source_host]
      source_name = payload["source_name"].presence || payload["source"].presence || attributes[:ats_name].presence || host
      slug = payload["source_slug"].presence || source_name.to_s.parameterize.presence || host.to_s.parameterize.presence || "manual"

      source = @source_resolver.resolve(name: source_name, slug:, host:) || JobSource.find_or_initialize_by(slug: slug)
      persist_source(source, attributes, payload, source_name).tap do |record|
        @source_resolver.register(record)
      end
    rescue ActiveRecord::RecordNotUnique
      recover_source(source_name:, slug:, host:)
    rescue ActiveRecord::RecordInvalid => error
      raise unless unique_source_conflict?(error.record)

      recover_source(source_name:, slug:, host:)
    end

    def find_existing_job(attributes)
      Job.find_by(fingerprint: attributes[:fingerprint]) ||
        Job.find_by(canonical_url: attributes[:canonical_url])
    end

    def persist_job(existing_job:, source:, attributes:, payload:)
      timestamp = Time.current
      job_attributes = attributes.merge(
        job_source: source,
        lifecycle_state: :active,
        last_seen_at: timestamp,
        last_validated_at: timestamp,
        raw_payload: payload
      ).except(:source_host)

      if existing_job
        update_existing_job(existing_job, job_attributes, attributes[:reason], payload)
      else
        create_job_or_recover(job_attributes:, attributes:, payload:, timestamp:)
      end
    end

    def persist_job_matches(job:, decisions:)
      timestamp = Time.current

      decisions.each do |decision|
        upsert_job_match(job, decision, timestamp)
      end
    end

    def mark_codex_fallback_seen!(source)
      return unless @search_run.trigger_source_codex_automation?
      return unless source.codex_fallback_enabled?

      source.update_columns(last_codex_checked_at: Time.current, last_codex_fallback_at: Time.current)
    end

    private
      def update_existing_job(existing_job, job_attributes, reason, payload)
        existing_job.assign_attributes(job_attributes.except(:user_state, :first_seen_at))

        outcome =
          if existing_job.changed?
            existing_job.save!
            @summary[:updated_count] += 1
            :updated
          else
            :skipped
          end

        build_run_item(existing_job, outcome, reason, payload)
        existing_job
      end

      def create_job_or_recover(job_attributes:, attributes:, payload:, timestamp:)
        job = nil
        Job.transaction(requires_new: true) do
          job = Job.create!(
            job_attributes.merge(
              user_state: :new_match,
              first_seen_at: timestamp
            )
          )
        end

        build_run_item(job, :created, attributes[:reason], payload)
        @summary[:imported_count] += 1
        job
      rescue ActiveRecord::RecordNotUnique
        recovered_job = find_existing_job(attributes)
        raise unless recovered_job

        update_existing_job(recovered_job, job_attributes, attributes[:reason], payload)
      rescue ActiveRecord::RecordInvalid => error
        raise unless unique_job_conflict?(error.record)

        recovered_job = find_existing_job(attributes)
        raise unless recovered_job

        update_existing_job(recovered_job, job_attributes, attributes[:reason], payload)
      end

      def upsert_job_match(job, decision, timestamp)
        match = job.job_matches.find_or_initialize_by(search_profile: decision.search_profile)
        assign_match_attributes(match, decision, timestamp)

        JobMatch.transaction(requires_new: true) do
          match.save!
        end
      rescue ActiveRecord::RecordNotUnique
        recover_job_match(job, decision, timestamp)
      rescue ActiveRecord::RecordInvalid => error
        raise unless unique_job_match_conflict?(error.record)

        recover_job_match(job, decision, timestamp)
      end

      def assign_match_attributes(match, decision, timestamp)
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

      def recover_job_match(job, decision, timestamp)
        match = job.job_matches.reset.find_by!(search_profile: decision.search_profile)
        assign_match_attributes(match, decision, timestamp)
        match.save!
      end

      def build_run_item(job, outcome, reason, payload)
        @search_run.search_run_items.create!(
          job:,
          outcome:,
          reason: reason.to_s,
          payload: payload,
          title: payload["title"].presence || payload["job_title"],
          company_name: payload["company"].presence || payload["company_name"],
          apply_url: payload["apply_url"].presence || payload["link"],
          canonical_url: payload["canonical_url"].presence || payload["source_url"]
        )
      end

      def persist_source(source, attributes, payload, source_name)
        source.tap do |record|
          record.name = source_name if record.name.blank?
          record.host = attributes[:source_host] if record.host.blank?
          record.base_url = attributes[:source_url].presence || attributes[:canonical_url] if record.base_url.blank?
          record.source_kind = normalize_source_kind(payload["source_kind"]) if record.new_record?
          record.enabled = true
          record.save!
        end
      end

      def recover_source(source_name:, slug:, host:)
        source = @source_resolver.resolve(name: source_name, slug:, host:) || JobSource.find_by!(slug: slug)
        @source_resolver.register(source)
        source
      rescue ActiveRecord::RecordNotFound
        JobSource.create!(
          name: source_name,
          slug: slug,
          host: host,
          base_url: host.present? ? "https://#{host}" : nil,
          source_kind: :ats
        ).tap { |source| @source_resolver.register(source) }
      end

      def unique_source_conflict?(record)
        record.is_a?(JobSource) && record.errors.of_kind?(:slug, :taken)
      end

      def unique_job_conflict?(record)
        record.is_a?(Job) &&
          (record.errors.of_kind?(:fingerprint, :taken) || record.errors.of_kind?(:canonical_url, :taken))
      end

      def unique_job_match_conflict?(record)
        record.is_a?(JobMatch) &&
          (record.errors.of_kind?(:job_id, :taken) || record.errors.of_kind?(:search_profile_id, :taken))
      end

      def normalize_source_kind(value)
        JobSource.source_kinds.fetch(value.to_s, JobSource.source_kinds.fetch("ats"))
      end
  end
end
