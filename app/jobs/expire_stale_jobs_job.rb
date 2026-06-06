class ExpireStaleJobsJob < ApplicationJob
  queue_as :default

  def perform
    stale_before = ENV.fetch("JOB_STALE_AFTER_DAYS", 21).to_i.days.ago

    Job.active.where(last_seen_at: ...stale_before).update_all(
      lifecycle_state: Job.lifecycle_states.fetch("expired"),
      updated_at: Time.current
    )
  end
end
