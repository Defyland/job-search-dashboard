require "test_helper"

class Waitlist::NotifierTest < ActiveSupport::TestCase
  test "deliver_new_entry sends the captured lead to the configured inbox" do
    entry = WaitlistEntry.new(
      email_address: "lead@example.com",
      ip_address: "127.0.0.1",
      created_at: Time.zone.parse("2026-06-11 10:00:00")
    )
    client = CapturingResendClient.new

    Waitlist::Notifier.new(client:, notify_to: "radar@example.com").deliver_new_entry!(entry)

    assert_equal "radar@example.com", client.payload.fetch(:to)
    assert_equal "lead@example.com", client.payload.fetch(:reply_to)
    assert_match "Nova inscricao na lista de espera do Farol", client.payload.fetch(:subject)
    assert_match "lead@example.com", client.payload.fetch(:text)
    assert_match "lead@example.com", client.payload.fetch(:html)
  end

  test "deliver_new_entry rejects missing target inbox" do
    entry = WaitlistEntry.new(email_address: "lead@example.com", created_at: Time.current)

    error = assert_raises(Resend::DeliveryError) do
      Waitlist::Notifier.new(client: CapturingResendClient.new, notify_to: nil).deliver_new_entry!(entry)
    end

    assert_equal "missing_waitlist_notify_to", error.message
  end

  private
    class CapturingResendClient
      attr_reader :payload

      def deliver!(**payload)
        @payload = payload
      end
    end
end
