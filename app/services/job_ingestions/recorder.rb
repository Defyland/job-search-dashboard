module JobIngestions
  class Recorder
    TRACKING_QUERY_KEYS = %w[fbclid gclid jobBoardSource utm_campaign utm_content utm_medium utm_source].freeze

    attr_reader :summary

    def initialize(search_run:)
      @search_run = search_run
      @summary = {
        imported_count: 0,
        updated_count: 0,
        expired_count: 0,
        rejected_count: 0
      }
    end

    def record_jobs(items)
      Array(items).each do |item|
        record_job(item)
      end
    end

    def record_rejections(items)
      Array(items).each do |item|
        payload = item.deep_stringify_keys
        build_run_item(nil, :rejected, payload["reason"].presence || "descartada pela automacao", payload)
        @summary[:rejected_count] += 1
      end
    end

    private
      def record_job(item)
        attributes = normalize_job_attributes(item)

        if attributes[:title].blank? || attributes[:company_name].blank? || attributes[:apply_url].blank?
          build_run_item(nil, :rejected, "vaga sem campos obrigatorios", item)
          @summary[:rejected_count] += 1
          return
        end

        source = find_or_create_source(attributes, item)
        existing_job = find_existing_job(attributes)

        if expired_payload?(item)
          if existing_job
            existing_job.update!(lifecycle_state: :expired, last_validated_at: Time.current)
            build_run_item(existing_job, :expired, attributes[:reason], item)
            @summary[:expired_count] += 1
          else
            build_run_item(nil, :rejected, "vaga expirada sem registro local", item)
            @summary[:rejected_count] += 1
          end
          return
        end

        upsert_job(existing_job:, source:, attributes:, payload: item)
      end

      def upsert_job(existing_job:, source:, attributes:, payload:)
        timestamp = Time.current
        job_attributes = attributes.merge(
          job_source: source,
          lifecycle_state: :active,
          last_seen_at: timestamp,
          last_validated_at: timestamp,
          raw_payload: payload
        ).except(:source_host)

        if existing_job
          existing_job.assign_attributes(job_attributes.except(:user_state, :first_seen_at))

          outcome =
            if existing_job.changed?
              existing_job.save!
              @summary[:updated_count] += 1
              :updated
            else
              :skipped
            end

          build_run_item(existing_job, outcome, attributes[:reason], payload)
        else
          job = Job.create!(
            job_attributes.merge(
              user_state: :new_match,
              first_seen_at: timestamp
            )
          )
          build_run_item(job, :created, attributes[:reason], payload)
          @summary[:imported_count] += 1
        end
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

      def find_or_create_source(attributes, payload)
        host = attributes[:source_host]
        source_name = payload["source_name"].presence || payload["source"].presence || attributes[:ats_name].presence || host
        slug = payload["source_slug"].presence || source_name.to_s.parameterize.presence || host.to_s.parameterize.presence || "manual"

        source = JobSource.resolve_for_ingestion(name: source_name, slug: slug, host: host) || JobSource.find_or_initialize_by(slug: slug)

        source.tap do |record|
          record.name = source_name if record.name.blank?
          record.host = host if record.host.blank?
          record.base_url = attributes[:source_url].presence || attributes[:canonical_url] if record.base_url.blank?
          record.source_kind = normalize_source_kind(payload["source_kind"]) if record.new_record?
          record.enabled = true
          record.save!
        end
      end

      def find_existing_job(attributes)
        Job.find_by(fingerprint: attributes[:fingerprint]) ||
          Job.find_by(canonical_url: attributes[:canonical_url])
      end

      def normalize_job_attributes(item)
        item = item.deep_stringify_keys
        apply_url = canonicalize_url(item["apply_url"].presence || item["direct_application_link"].presence || item["link"])
        source_url = canonicalize_url(item["source_url"].presence || item["job_url"].presence || item["source_page"])
        canonical_url = canonicalize_url(item["canonical_url"].presence || source_url || apply_url)
        published_at = parse_time(item["published_at"]) || parse_time(item["last_updated_at"])

        {
          title: item["title"].presence || item["job_title"].to_s.squish,
          company_name: item["company"].presence || item["company_name"].to_s.squish,
          apply_url: apply_url,
          canonical_url: canonical_url,
          source_url: source_url || canonical_url,
          ats_name: item["source_name"].presence || item["source"].presence,
          external_job_id: item["external_job_id"].presence || item["job_id"].presence,
          remote_text: item["remote_signal"].presence || item["remote"].presence || item["location"].presence,
          location_text: item["location"].presence || item["location_text"].presence,
          seniority: item["seniority"].presence || "senior",
          match_strength: normalize_match_strength(item["match_strength"]),
          reason: item["reason"].presence || item["match_reason"].presence || "match validado pela automacao",
          score: normalize_score(item),
          posted_text: item["recency_text"].presence || item["posted_text"].presence,
          published_at:,
          fingerprint: normalize_fingerprint(item, canonical_url, apply_url),
          stack_tags: normalize_stack_tags(item),
          source_host: normalize_host(canonical_url || apply_url),
          user_state: :new_match
        }
      end

      def normalize_stack_tags(item)
        Array(item["stack_tags"].presence || item["stack_match"].presence || item["stack"]).flat_map { |value| value.to_s.split(",") }
                                                                                                 .map { |value| value.downcase.squish }
                                                                                                 .reject(&:blank?)
                                                                                                 .uniq
      end

      def normalize_fingerprint(item, canonical_url, apply_url)
        explicit_fingerprint = item["fingerprint"].to_s.strip
        return explicit_fingerprint if explicit_fingerprint.present?

        [
          item["company"].presence || item["company_name"],
          item["title"].presence || item["job_title"],
          normalize_host(canonical_url || apply_url),
          item["external_job_id"].presence || item["job_id"]
        ].map { |value| value.to_s.downcase.squish }
         .reject(&:blank?)
         .join("::")
      end

      def normalize_match_strength(value)
        Job.match_strengths.fetch(value.to_s, Job.match_strengths.fetch("strong"))
      end

      def normalize_source_kind(value)
        JobSource.source_kinds.fetch(value.to_s, JobSource.source_kinds.fetch("ats"))
      end

      def normalize_score(item)
        return item["score"].to_i if item["score"].present?

        base_score = normalize_match_strength(item["match_strength"]) == Job.match_strengths.fetch("strong") ? 90 : 70
        base_score += 5 if parse_time(item["published_at"]).present? && parse_time(item["published_at"]) >= 24.hours.ago
        base_score
      end

      def canonicalize_url(url)
        return if url.blank?

        uri = URI.parse(url.to_s.strip)
        uri.fragment = nil

        if uri.query.present?
          filtered_query = URI.decode_www_form(uri.query).reject { |(key, _)| TRACKING_QUERY_KEYS.include?(key) }
          uri.query = filtered_query.any? ? URI.encode_www_form(filtered_query) : nil
        end

        uri.to_s.delete_suffix("/")
      rescue URI::InvalidURIError
        url.to_s.strip.delete_suffix("/")
      end

      def normalize_host(url)
        URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "")
      rescue URI::InvalidURIError, NoMethodError
        ""
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def expired_payload?(item)
        status = item["status"].to_s.downcase
        return true if item["active"] == false

        %w[closed expired unavailable inactive].include?(status)
      end
  end
end
