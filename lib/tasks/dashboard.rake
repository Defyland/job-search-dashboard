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
    JobSource.seed_defaults!
    puts "Fontes sincronizadas: #{JobSource.count}"
  end
end
