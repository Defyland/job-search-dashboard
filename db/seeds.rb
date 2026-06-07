JobSources::Catalog.seed!

if Rails.env.development?
  admin = User.find_or_initialize_by(email_address: ENV.fetch("ADMIN_EMAIL", "admin@example.com"))
  admin.password = ENV.fetch("ADMIN_PASSWORD", "change-me-now") if admin.new_record?
  admin.save!
  SearchProfile.ensure_default_for(admin)
end
