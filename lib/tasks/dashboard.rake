namespace :dashboard do
  desc "Create or update the admin user from ADMIN_EMAIL and ADMIN_PASSWORD"
  task bootstrap_admin: :environment do
    email = ENV.fetch("ADMIN_EMAIL")
    password = ENV.fetch("ADMIN_PASSWORD")

    user = User.find_or_initialize_by(email_address: email)
    user.password = password if user.new_record? || ENV["ADMIN_RESET_PASSWORD"].present?
    user.admin = true
    user.save!

    puts "Admin pronto: #{user.email_address}"
  end

  desc "Seed the supported source catalog"
  task seed_sources: :environment do
    JobSources::Catalog.seed!
    puts "Fontes sincronizadas: #{JobSource.count}"
  end

  desc "Run the deterministic Rails discovery backfill"
  task :discover, [ :window_days ] => :environment do |_task, args|
    window_days = (args[:window_days].presence&.to_i || 20).clamp(1, 30)
    result = JobDiscovery::Orchestrator.new(window_days:, trigger_source: :manual).call

    if result.success?
      puts "Run ##{result.search_run.id} concluido: #{result.summary.inspect}"
    else
      abort("Falha no backfill: #{result.errors.join(', ')}")
    end
  end

  desc "Regenerate persisted profile variations (dry-run unless APPLY=1)"
  task backfill_profile_variations: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "0"))
    enqueue_sync = ActiveModel::Type::Boolean.new.cast(ENV.fetch("SYNC", "0"))
    profile_id = ENV["PROFILE_ID"].presence
    batch_size = ENV.fetch("BATCH_SIZE", "100").to_i.clamp(1, 1_000)
    scope = profile_id ? SearchProfile.where(id: profile_id) : SearchProfile.all

    abort("Perfil nao encontrado: #{profile_id}") if profile_id && !scope.exists?
    abort("SYNC=1 exige APPLY=1") if enqueue_sync && !apply

    counts = Hash.new(0)
    failures = []

    scope.find_each(batch_size:) do |profile|
      result = SearchProfiles::VariationBackfill.new(profile:, apply:).call
      counts[result.status] += 1
      puts "profile=#{profile.id} status=#{result.status} added_stacks=#{result.added_stacks.join(',')} stacks=#{result.after_stacks.join(',')}"

      if apply && enqueue_sync && result.status == :updated
        SearchProfiles::SyncRequest.new(search_profile: profile, prune_stale: true).call
        counts[:sync_enqueued] += 1
      end
    rescue StandardError => error
      failures << [ profile.id, error ]
      warn "profile=#{profile.id} status=failed error=#{error.class}: #{error.message}"
    end

    puts "mode=#{apply ? 'apply' : 'dry-run'} counts=#{counts.sort.to_h.inspect} failures=#{failures.size}"
    abort("Backfill terminou com #{failures.size} falha(s)") if failures.any?
  end
end
