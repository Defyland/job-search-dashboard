module JobDiscovery
  module SearchIndex
    class BoardSeeder
      DEFAULT_MAX_QUERIES = 60
      DEFAULT_RESULTS_PER_QUERY = 10

      Result = Struct.new(:enabled, :query_count, :result_count, :seeded_count, :errors, keyword_init: true) do
        def to_h
          {
            enabled:,
            query_count:,
            result_count:,
            seeded_count:,
            errors:
          }
        end
      end

      def initialize(
        search_profiles:,
        sources: JobSource.backfillable,
        client: Client.new,
        classifier: UrlClassifier.new,
        max_queries: Integer(ENV.fetch("SEARCH_INDEX_MAX_QUERIES", DEFAULT_MAX_QUERIES)),
        results_per_query: Integer(ENV.fetch("SEARCH_INDEX_RESULTS_PER_QUERY", DEFAULT_RESULTS_PER_QUERY))
      )
        @search_profiles = Array(search_profiles)
        @sources = sources.to_a
        @client = client
        @classifier = classifier
        @max_queries = max_queries
        @results_per_query = results_per_query
        @errors = []
      end

      def call
        return result(enabled: false) unless @client.enabled?

        queries.each do |query|
          search(query)
        end

        result(enabled: true, seeded_count: persist_additions)
      end

      private
        def queries
          @queries ||= QueryBuilder.new(search_profiles: @search_profiles, targets: adapter_seed_targets)
                                   .queries(limit: @max_queries)
        end

        def search(query)
          @client.search(query.query, max_results: @results_per_query).each do |search_result|
            @result_count = result_count + 1
            track_discovery(search_result.url)
          end
        rescue StandardError => error
          @errors << "#{query.host}: #{error.message}"
        end

        def track_discovery(url)
          discovery = @classifier.call(url)
          return unless discovery
          return unless sources_by_slug.key?(discovery.source_slug)

          additions[discovery.source_slug][discovery.setting_key] << discovery.setting_value
        end

        def persist_additions
          additions.sum do |source_slug, settings|
            source = sources_by_slug.fetch(source_slug)
            settings.sum do |setting_key, values|
              merge_setting_values(source, setting_key, values.uniq)
            end
          end
        end

        def merge_setting_values(source, setting_key, values)
          source.with_lock do
            settings = source.settings.deep_dup
            existing = Array(settings[setting_key]).map(&:to_s)
            new_values = values - existing
            next 0 if new_values.empty?

            settings[setting_key] = (existing + new_values).uniq
            source.update!(settings:)
            new_values.size
          end
        end

        def adapter_seed_targets
          QueryBuilder::TARGETS.select do |target|
            target[:setting_key].present? && sources_by_slug.key?(target[:source_slug])
          end
        end

        def additions
          @additions ||= Hash.new { |source_hash, source_slug| source_hash[source_slug] = Hash.new { |setting_hash, setting_key| setting_hash[setting_key] = [] } }
        end

        def sources_by_slug
          @sources_by_slug ||= @sources.index_by(&:slug)
        end

        def result(enabled:, seeded_count: 0)
          Result.new(
            enabled:,
            query_count: enabled ? queries.size : 0,
            result_count:,
            seeded_count:,
            errors: @errors
          )
        end

        def result_count
          @result_count ||= 0
        end
    end
  end
end
