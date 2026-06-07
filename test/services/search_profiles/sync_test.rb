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
      Result = Struct.new(:errors, keyword_init: true)

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
        Result.new(errors: [])
      end
    end

    class ErroringDiscoveredBootstrapper < FakeDiscoveredBootstrapper
      def call
        FakeDiscoveredBootstrapper.calls << @search_profile.id
        Result.new(errors: [ "cache import failed" ])
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

      result = Sync.new(
        search_profile: profile,
        prune_stale: true,
        bootstrapper_class: FakeBootstrapper,
        discovered_bootstrapper_class: FakeDiscoveredBootstrapper,
        run_job_class: FakeRunJob
      ).call

      assert result.success?
      assert result.external_run_enqueued
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

    test "does nothing for inactive profiles" do
      profile = search_profiles(:default)
      profile.update!(active: false)

      result = Sync.new(
        search_profile: profile,
        prune_stale: true,
        bootstrapper_class: FakeBootstrapper,
        discovered_bootstrapper_class: FakeDiscoveredBootstrapper,
        run_job_class: FakeRunJob
      ).call

      assert result.success?
      refute result.external_run_enqueued
      assert_empty FakeBootstrapper.calls
      assert_empty FakeDiscoveredBootstrapper.calls
      assert_empty FakeRunJob.calls
    end

    test "reports discovered cache errors while still enqueueing the external run" do
      profile = search_profiles(:default)

      result = Sync.new(
        search_profile: profile,
        prune_stale: false,
        bootstrapper_class: FakeBootstrapper,
        discovered_bootstrapper_class: ErroringDiscoveredBootstrapper,
        run_job_class: FakeRunJob
      ).call

      refute result.success?
      assert_equal [ "cache import failed" ], result.errors
      assert result.external_run_enqueued
      assert_equal [ profile.id ], FakeDiscoveredBootstrapper.calls
      assert_equal 1, FakeRunJob.calls.size
    end
  end
end
