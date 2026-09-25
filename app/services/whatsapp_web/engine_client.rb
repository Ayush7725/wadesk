# WaDesk: client for the internal wadesk-engine session API (docs/wadesk/02-architecture.md §4.1).
class WhatsappWeb::EngineClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code, message)
      @status = status
      @code = code
      super("wadesk-engine #{status} #{code}: #{message}")
    end
  end

  TIMEOUT_SECONDS = 10

  def upsert_session(channel)
    request(:put, "/sessions/#{channel.id}", {
              phone_number: channel.phone_number.delete_prefix('+'),
              webhook_url: "#{callback_base_url}/webhooks/whatsapp_web/#{channel.id}",
              link_method: channel.provider_config['link_method']
            })
  end

  def session(channel_id)
    request(:get, "/sessions/#{channel_id}")
  end

  # Idempotent: a session the engine does not know is already gone.
  def delete_session(channel_id)
    request(:delete, "/sessions/#{channel_id}")
  rescue Error => e
    raise unless e.code == 'session_not_found'
  end

  private

  def request(method, path, body = nil)
    headers = { 'Authorization' => "Bearer #{ENV.fetch('WADESK_ENGINE_API_TOKEN')}" }
    # The engine rejects a JSON content type without a body (GET/DELETE).
    headers['Content-Type'] = 'application/json' if body
    response = HTTParty.public_send(method, "#{ENV.fetch('WADESK_ENGINE_URL')}#{path}",
                                    headers: headers, body: body&.to_json, timeout: TIMEOUT_SECONDS)
    return response.parsed_response if response.success?

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response.fetch('error', {}) : {}
    raise Error.new(response.code, error['code'], error['message'] || response.body)
  end

  # Chatwoot's base URL as reachable from the engine (internal network), defaulting to FRONTEND_URL.
  def callback_base_url
    ENV.fetch('WADESK_ENGINE_CALLBACK_BASE_URL') { ENV.fetch('FRONTEND_URL') }
  end
end
