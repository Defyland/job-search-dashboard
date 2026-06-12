module Waitlist
  class Notifier
    def initialize(client: Resend::Client.new, notify_to: ENV["WAITLIST_NOTIFY_TO"].presence || ENV["RESEND_WAITLIST_TO"])
      @client = client
      @notify_to = notify_to.to_s
    end

    def deliver_new_entry!(entry)
      raise Resend::DeliveryError, "missing_waitlist_notify_to" if notify_to.blank?

      client.deliver!(
        to: notify_to,
        reply_to: entry.email_address,
        subject: "Nova inscricao na lista de espera do Farol",
        text: text_body(entry),
        html: html_body(entry)
      )
    end

    private
      attr_reader :client, :notify_to

      def text_body(entry)
        <<~TEXT
          Novo email na lista de espera do Farol.

          Email: #{entry.email_address}
          Capturado em: #{I18n.l(entry.created_at.in_time_zone("America/Sao_Paulo"), format: :long)}
          IP: #{entry.ip_address.presence || "indisponivel"}
        TEXT
      end

      def html_body(entry)
        <<~HTML
          <div style="font-family:Arial,sans-serif;background:#06090f;color:#eef2fb;padding:32px">
            <p style="margin:0 0 12px;font-size:12px;letter-spacing:3px;color:#f6b54a">FAROL</p>
            <h1 style="margin:0 0 16px;font-size:24px;color:#ffffff">Nova inscricao na lista de espera</h1>
            <p style="margin:0 0 12px;color:#9aa7c4">O formulario publico acabou de capturar um novo contato.</p>
            <div style="padding:18px 20px;border-radius:16px;background:#0f1830;border:1px solid rgba(233,238,252,0.12)">
              <p style="margin:0 0 10px;color:#9aa7c4">Email</p>
              <p style="margin:0 0 16px;font-size:20px;font-weight:700;color:#ffffff">#{ERB::Util.html_escape(entry.email_address)}</p>
              <p style="margin:0 0 6px;color:#9aa7c4">Capturado em</p>
              <p style="margin:0 0 6px;color:#ffffff">#{ERB::Util.html_escape(I18n.l(entry.created_at.in_time_zone("America/Sao_Paulo"), format: :long))}</p>
              <p style="margin:0 0 6px;color:#9aa7c4">IP</p>
              <p style="margin:0;color:#ffffff">#{ERB::Util.html_escape(entry.ip_address.presence || "indisponivel")}</p>
            </div>
          </div>
        HTML
      end
  end
end
