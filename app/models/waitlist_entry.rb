class WaitlistEntry < ApplicationRecord
  normalizes :email_address, with: ->(value) { value.to_s.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
end
