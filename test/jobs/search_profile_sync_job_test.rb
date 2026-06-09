require "test_helper"

class SearchProfileSyncJobTest < ActiveJob::TestCase
  class FakeSync
    def initialize(result = nil, error: nil)
      @result = result
      @error = error
    end

    def call
      raise @error if @error

      @result
    end
  end

  test "marks the profile as synced when the local refresh succeeds" do
    profile = search_profiles(:default)
    profile.update!(sync_state: :pending)
    result = SearchProfiles::Sync::Result.new(discovered_bootstrap_result: nil, external_run_enqueued: true, errors: [])

    with_fake_sync(FakeSync.new(result)) do
      SearchProfileSyncJob.perform_now(search_profile_id: profile.id, prune_stale: true)
    end

    assert_equal "synced", profile.reload.sync_state
    assert_nil profile.last_sync_error
    assert profile.last_synced_at.present?
  end

  test "marks the profile as failed when the local refresh returns errors" do
    profile = search_profiles(:default)
    result = SearchProfiles::Sync::Result.new(
      discovered_bootstrap_result: nil,
      external_run_enqueued: true,
      errors: [ "cache import failed" ]
    )

    with_fake_sync(FakeSync.new(result)) do
      SearchProfileSyncJob.perform_now(search_profile_id: profile.id, prune_stale: false)
    end

    assert_equal "failed", profile.reload.sync_state
    assert_equal "cache import failed", profile.last_sync_error
  end

  test "marks the profile as failed and re-raises unexpected sync errors" do
    profile = search_profiles(:default)

    assert_raises(StandardError) do
      with_fake_sync(FakeSync.new(error: StandardError.new("boom"))) do
        SearchProfileSyncJob.perform_now(search_profile_id: profile.id, prune_stale: false)
      end
    end

    assert_equal "failed", profile.reload.sync_state
    assert_equal "boom", profile.last_sync_error
  end

  test "marks inactive profiles as idle without running sync" do
    profile = search_profiles(:default)
    profile.update!(active: false, sync_state: :pending)

    with_fake_sync(FakeSync.new(SearchProfiles::Sync::Result.new(discovered_bootstrap_result: nil, external_run_enqueued: true, errors: []))) do
      SearchProfileSyncJob.perform_now(search_profile_id: profile.id, prune_stale: false)
    end

    assert_equal "idle", profile.reload.sync_state
    assert_nil profile.last_sync_error
  end

  private
    def with_fake_sync(fake_sync)
      original_new = SearchProfiles::Sync.method(:new)
      SearchProfiles::Sync.singleton_class.send(:define_method, :new) { |_args = nil, **_kwargs| fake_sync }
      yield
    ensure
      SearchProfiles::Sync.singleton_class.send(:define_method, :new) do |*args, **kwargs|
        original_new.call(*args, **kwargs)
      end
    end
end
