namespace :dashboard do
  desc "Create or update the admin user from ADMIN_EMAIL and ADMIN_PASSWORD"
  task bootstrap_admin: :environment do
    email = ENV.fetch("ADMIN_EMAIL")
    password = ENV.fetch("ADMIN_PASSWORD")

    user = User.find_or_initialize_by(email_address: email)
    user.password = password if user.new_record? || ENV["ADMIN_RESET_PASSWORD"].present?
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
end
