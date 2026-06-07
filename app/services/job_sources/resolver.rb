module JobSources
  class Resolver
    def initialize(scope: JobSource.all)
      @scope = scope
      @host_cache = {}
      reload!
    end

    def resolve(name:, slug:, host:)
      normalized_slug = slug.to_s.parameterize
      return @sources_by_slug[normalized_slug] if normalized_slug.present? && @sources_by_slug.key?(normalized_slug)

      normalized_name = normalize_lookup_key(name)
      return @sources_by_name[normalized_name] if normalized_name.present? && @sources_by_name.key?(normalized_name)

      normalized_host = normalize_host(host)
      return if normalized_host.blank?

      @host_cache.fetch(normalized_host) do
        @host_cache[normalized_host] = @ordered_sources.find { |source| host_matches?(normalized_host, source.host) }
      end
    end

    def register(source)
      return unless source

      @ordered_sources.reject! { |entry| entry.id == source.id }
      @ordered_sources << source
      @ordered_sources.sort_by! { |entry| [ -entry.host.to_s.length, entry.priority, entry.name ] }

      @sources_by_slug[source.slug] = source if source.slug.present?

      normalized_name = normalize_lookup_key(source.name)
      @sources_by_name[normalized_name] = source if normalized_name.present?

      normalized_host = normalize_host(source.host)
      @host_cache.delete(normalized_host) if normalized_host.present?
    end

    private
      def reload!
        @ordered_sources = @scope.to_a.sort_by { |source| [ -source.host.to_s.length, source.priority, source.name ] }
        @sources_by_slug = @ordered_sources.index_by(&:slug)
        @sources_by_name = @ordered_sources.each_with_object({}) do |source, result|
          normalized_name = normalize_lookup_key(source.name)
          next if normalized_name.blank? || result.key?(normalized_name)

          result[normalized_name] = source
        end
      end

      def normalize_lookup_key(value)
        value.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      def normalize_host(value)
        value.to_s.downcase.sub(/\Awww\./, "")
      end

      def host_matches?(candidate_host, existing_host)
        return false if candidate_host.blank? || existing_host.blank?

        candidate_host == existing_host ||
          candidate_host.end_with?(".#{existing_host}") ||
          existing_host.end_with?(".#{candidate_host}")
      end
  end
end
