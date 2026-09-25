# WaDesk: receives events from the internal wadesk-engine (docs/wadesk/02-architecture.md §4.2).
class Webhooks::WhatsappWebController < ActionController::API
  REPLAY_WINDOW = 5.minutes

  before_action :verify_signature!

  # The engine sends a channel's next event only after this one is acknowledged, so handling connection
  # events inline keeps them in order (a queue with parallel workers could apply them out of order).
  def process_payload
    channel = Channel::Whatsapp.find_by(id: params[:channel_id], provider: 'baileys')
    # The inbox was deleted: acknowledge so the engine stops retrying events nobody can use.
    return head :ok if channel.blank?

    case payload['event']
    when 'connection' then WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: payload).perform
    # Same pipeline as the other WhatsApp providers (payloads use the Cloud API message shape, ADR-0003).
    # The job locks per sender and finds the channel by its phone number.
    when 'messages' then Webhooks::WhatsappEventsJob.perform_later(payload.with_indifferent_access.merge(phone_number: channel.phone_number))
    else return render json: { error: "Unsupported event: #{payload['event']}" }, status: :unprocessable_entity
    end
    head :ok
  end

  private

  def payload
    @payload ||= JSON.parse(request.raw_post)
  end

  # sha256=HMAC(secret, "<timestamp>.<raw body>"), rejected outside the replay window.
  def verify_signature!
    timestamp = request.headers['X-WaDesk-Timestamp'].to_s
    signature = request.headers['X-WaDesk-Signature'].to_s
    fresh = timestamp.match?(/\A\d+\z/) && (Time.zone.now.to_i - timestamp.to_i).abs <= REPLAY_WINDOW
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('WADESK_ENGINE_WEBHOOK_SECRET'), "#{timestamp}.#{request.raw_post}")}"

    head :unauthorized unless fresh && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end
end
