class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :search_profiles, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
end
