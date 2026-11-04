module JobDiscovery
  module SearchIndex
    class BoardSeeder
      DEFAULT_MAX_QUERIES = 60
      DEFAULT_RESULTS_PER_QUERY = 10

      Result = Struct.new(:enabled, :query_count, :result_count, :seeded_count, :errors, :queries, keyword_init: true) do
        def to_h
          {
            enabled:,
            query_count:,
            result_count:,
            seeded_count:,
            errors:,
            queries:
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
        @query_entries = []
        @known_values = known_values_from(@sources)
        @discovered_values = Set.new
      end

      def call
        return result(enabled: false) unless @client.enabled?

        queries.each do |query|
          search(query)
        end

        # A concurrent writer can persist a value first, so sum(discovered_seed_count) may exceed seeded_count.
        result(enabled: true, seeded_count: persist_additions)
      end

      private
        def queries
          @queries ||= QueryBuilder.new(search_profiles: @search_profiles, targets: adapter_seed_targets)
                                   .queries(limit: @max_queries)
        end

        def search(query)
          entry = query_entry(query)
          @client.search(query.query, max_results: @results_per_query).each do |search_result|
            @result_count = result_count + 1
            entry[:result_count] += 1
            track_discovery(search_result.url, entry)
          end
        rescue StandardError => error
          @errors << "#{query.host}: #{error.message}"
          entry[:error] = error.class.name
        end

        def query_entry(query)
          {
            host: query.host,
            source_slug: query.source_slug,
            target_stack: query.target_stack,
            search_profile_ids: query.search_profile_ids,
            result_count: 0,
            discovered_seed_count: 0
          }.tap { |entry| @query_entries << entry }
        end

        def track_discovery(url, entry)
          discovery = @classifier.call(url)
          return unless discovery
          return unless sources_by_slug.key?(discovery.source_slug)

          additions[discovery.source_slug][discovery.setting_key] << discovery.setting_value

          value_key = [ discovery.source_slug, discovery.setting_key, discovery.setting_value ]
          return if @known_values.include?(value_key) || !@discovered_values.add?(value_key)

          entry[:discovered_seed_count] += 1
        end

        def known_values_from(sources)
          sources.each_with_object(Set.new) do |source, known|
            source.settings.each do |setting_key, values|
              Array(values).each { |value| known << [ source.slug, setting_key.to_s, value.to_s.dup ] }
            end
          end
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
            errors: @errors,
            queries: @query_entries
          )
        end

        def result_count
          @result_count ||= 0
        end
    end
  end
end
