require "test_helper"

class WaitlistEntriesControllerTest < ActionDispatch::IntegrationTest
  test "create stores a new waitlist email and notifies via Resend" do
    notifier = CapturingWaitlistNotifier.new

    with_replaced_singleton_method(Waitlist::Notifier, :new, notifier) do
      assert_difference("WaitlistEntry.count", 1) do
        post waitlist_entries_path, params: { waitlist_entry: { email_address: "  NewLead@example.com " } }
      end
    end

    entry = WaitlistEntry.order(:id).last

    assert_redirected_to root_path(anchor: "entrar")
    assert_equal "newlead@example.com", entry.email_address
    assert_equal [ entry.email_address ], notifier.delivered_email_addresses
    assert_not_nil entry.notified_at
    assert_nil entry.notification_error

    follow_redirect!
    assert_select ".flash.notice", text: "Email salvo. Quando a lista abrir, eu te aviso."
  end

  test "create treats duplicate waitlist email as a no-op" do
    WaitlistEntry.create!(email_address: "repeat@example.com")

    with_replaced_singleton_method(Waitlist::Notifier, :new, RaisingWaitlistNotifier.new) do
      assert_no_difference("WaitlistEntry.count") do
        post waitlist_entries_path, params: { waitlist_entry: { email_address: "repeat@example.com" } }
      end
    end

    assert_redirected_to root_path(anchor: "entrar")

    follow_redirect!
    assert_select ".flash.notice", text: "Esse email ja esta na lista."
  end

  test "create re-renders landing feedback for invalid email" do
    assert_no_difference("WaitlistEntry.count") do
      post waitlist_entries_path, params: { waitlist_entry: { email_address: "sem-arroba" } }
    end

    assert_redirected_to root_path(anchor: "entrar")

    follow_redirect!
    assert_select ".flash.alert", text: "Email address is invalid"
    assert_select "form#capform input[type=email][value=?]", "sem-arroba"
  end

  test "create keeps the lead when Resend notification fails" do
    with_replaced_singleton_method(Waitlist::Notifier, :new, FailingWaitlistNotifier.new) do
      assert_difference("WaitlistEntry.count", 1) do
        post waitlist_entries_path, params: { waitlist_entry: { email_address: "notifyfail@example.com" } }
      end
    end

    entry = WaitlistEntry.order(:id).last

    assert_redirected_to root_path(anchor: "entrar")
    assert_nil entry.notified_at
    assert_equal "resend_503", entry.notification_error

    follow_redirect!
    assert_select ".flash.notice", text: "Email salvo. Quando a lista abrir, eu te aviso."
  end

  private
    def with_replaced_singleton_method(klass, method_name, replacement)
      singleton_class = klass.singleton_class
      original_method = singleton_class.instance_method(method_name)

      singleton_class.define_method(method_name) do |*args, **kwargs, &block|
        if replacement.respond_to?(:call)
          replacement.call(*args, **kwargs, &block)
        else
          replacement
        end
      end

      yield
    ensure
      singleton_class.define_method(method_name, original_method)
    end

    class CapturingWaitlistNotifier
      attr_reader :delivered_email_addresses

      def initialize
        @delivered_email_addresses = []
      end

      def deliver_new_entry!(entry)
        @delivered_email_addresses << entry.email_address
      end
    end

    class RaisingWaitlistNotifier
      def deliver_new_entry!(_entry)
        raise "should not notify duplicates"
      end
    end

    class FailingWaitlistNotifier
      def deliver_new_entry!(_entry)
        raise Resend::DeliveryError, "resend_503"
      end
    end
end
