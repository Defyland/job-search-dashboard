module JobIngestions
  class Recorder
    def initialize(search_run:)
      @matcher = JobMatching::ProfileMatcher.new
      @normalizer = PayloadNormalizer.new
      @store = Store.new(search_run:)
    end

    def record_jobs(items)
      Array(items).each do |item|
        record_job(item)
      end
    end

    def record_rejections(items)
      Array(items).each do |item|
        payload = item.deep_stringify_keys
        @store.reject(payload:, reason: payload["reason"].presence || "descartada pela automacao")
      end
    end

    def summary
      @store.summary
    end

    private
      def record_job(item)
        attributes = @normalizer.normalize(item)

        if attributes[:title].blank? || attributes[:company_name].blank? || attributes[:apply_url].blank?
          @store.reject(payload: item, reason: "vaga sem campos obrigatorios")
          return
        end

        source = @store.resolve_source(attributes:, payload: item)
        existing_job = @store.find_existing_job(attributes)

        if @normalizer.expired?(item)
          @store.expire(existing_job:, reason: attributes[:reason], payload: item)
          return
        end

        profile_decisions = profile_decisions_for(attributes, item, source)
        accepted_decisions = profile_decisions.select(&:accepted?)
        if accepted_decisions.blank?
          @store.reject(payload: item, reason: rejection_reason_for(profile_decisions))
          return
        end

        primary_decision = accepted_decisions.max_by(&:score)
        attributes = apply_policy_decision(attributes, primary_decision)

        job = @store.persist_job(existing_job:, source:, attributes:, payload: item)
        @store.persist_job_matches(job:, decisions: accepted_decisions)
        @store.mark_codex_fallback_seen!(source)
      end

      def profile_decisions_for(attributes, item, source)
        @matcher.decisions(attributes:, payload: item, source:)
      end

      def rejection_reason_for(decisions)
        decisions.map { |decision| decision.exclusion_reason.presence || decision.reason }
                 .compact_blank
                 .tally
                 .max_by { |_reason, count| count }
                 &.first || "nenhum perfil ativo aceitou a vaga"
      end

      def apply_policy_decision(attributes, decision)
        attributes.merge(
          match_strength: Job.match_strengths.fetch(decision.classification.to_s),
          reason: decision.reason,
          score: decision.score,
          seniority: decision.seniority,
          stack_tags: decision.stack_tags,
          remote_text: decision.remote_signal.presence || attributes[:remote_text]
        )
      end
  end
end
