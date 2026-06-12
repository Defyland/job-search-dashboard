class WaitlistEntriesController < ApplicationController
  allow_unauthenticated_access only: :create
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to root_path(anchor: "entrar"), alert: "Tente novamente em alguns minutos." }

  def create
    entry = WaitlistEntry.find_or_initialize_by(email_address: normalized_email_address)

    if entry.persisted?
      redirect_to root_path(anchor: "entrar"), notice: "Esse email ja esta na lista."
      return
    end

    entry.ip_address = request.remote_ip
    entry.user_agent = request.user_agent

    if entry.save
      notify_waitlist(entry)
      redirect_to root_path(anchor: "entrar"), notice: "Email salvo. Quando a lista abrir, eu te aviso."
    else
      flash[:waitlist_email] = entry.email_address
      redirect_to root_path(anchor: "entrar"), alert: entry.errors.full_messages.to_sentence
    end
  end

  private
    def normalized_email_address
      waitlist_entry_params.fetch(:email_address).to_s.strip.downcase
    end

    def waitlist_entry_params
      params.expect(waitlist_entry: [ :email_address ])
    end

    def notify_waitlist(entry)
      Waitlist::Notifier.new.deliver_new_entry!(entry)
      entry.update!(notified_at: Time.current, notification_error: nil)
    rescue Resend::DeliveryError => error
      entry.update!(notification_error: error.message)
      Rails.logger.error("[waitlist] Resend delivery failed for #{entry.email_address}: #{error.message}")
    end
end
