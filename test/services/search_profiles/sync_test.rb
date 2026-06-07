require "test_helper"

module SearchProfiles
  class SyncTest < ActiveSupport::TestCase
    class FakeBootstrapper
      class << self
        attr_reader :calls

        def reset!
          @calls = []
        end
      end

      def initialize(search_profile:, prune_stale:)
        @search_profile = search_profile
        @prune_stale = prune_stale
      end

      def call
        self.class.calls << [ @search_profile.id, @prune_stale ]
      end
    end

    class FakeDiscoveredBootstrapper
      class << self
        attr_reader :calls

        def reset!
          @calls = []
        end
      end

      def initialize(search_profile:)
        @search_profile = search_profile
      end

      def call
        self.class.calls << @search_profile.id
      end
    end

    class FakeRunJob
      class << self
        attr_reader :calls

        def reset!
          @calls = []
        end

        def perform_later(**kwargs)
          @calls << kwargs
        end
      end
    end

    setup do
      FakeBootstrapper.reset!
      FakeDiscoveredBootstrapper.reset!
      FakeRunJob.reset!
    end

    test "runs local bootstrap, discovered cache bootstrap, and profile-scoped discovery" do
      profile = search_profiles(:default)

      Sync.new(
        search_profile: profile,
        prune_stale: true,
        bootstrapper_class: FakeBootstrapper,
        discovered_bootstrapper_class: FakeDiscoveredBootstrapper,
        run_job_class: FakeRunJob
      ).call

      assert_equal [ [ profile.id, true ] ], FakeBootstrapper.calls
      assert_equal [ profile.id ], FakeDiscoveredBootstrapper.calls
      assert_equal [
        {
          window_days: profile.scan_window_days,
          trigger_source: :manual,
          search_profile_id: profile.id
        }
      ], FakeRunJob.calls
    end
  end
end
