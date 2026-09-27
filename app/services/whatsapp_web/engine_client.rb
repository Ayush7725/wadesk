# WaDesk: client for the internal wadesk-engine session API (docs/wadesk/02-architecture.md §4.1).
class WhatsappWeb::EngineClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code, message)
      @status = status
      @code = code
      super("wadesk-engine #{status} #{code}: #{message}")
    end

    # Worth retrying later (rate limit, engine trouble) rather than failing the message now.
    def retryable?
      status == 429 || status >= 500
    end
  end

  # A file part for multipart uploads; HTTParty reads the name and type from it.
  UploadPart = Struct.new(:io, :original_filename, :content_type) do
    delegate :read, :rewind, to: :io

    def path = original_filename
  end

  TIMEOUT_SECONDS = 10
  SEND_TIMEOUT_SECONDS = 60 # uploads of large files
  HEALTH_TIMEOUT_SECONDS = 3 # the operator's System health page must never hang on the engine

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

  # Sends a text or one file on the channel's WhatsApp Web number; returns WhatsApp's message id.
  def send_message(channel_id, parts)
    # stream_body: false — HTTParty 0.24's streaming multipart (used when a file is present) omits the blank line
    # after each plain field's headers, which the engine rightly rejects as malformed. The file is in memory anyway.
    response = HTTParty.post("#{ENV.fetch('WADESK_ENGINE_URL')}/sessions/#{channel_id}/messages",
                             headers: auth_headers, body: parts.compact, multipart: true, stream_body: false,
                             timeout: SEND_TIMEOUT_SECONDS)
    raise_error(response) unless response.success?

    response.parsed_response.fetch('id')
  end

  # Idempotent: a session the engine does not know is already gone.
  def delete_session(channel_id)
    request(:delete, "/sessions/#{channel_id}")
  rescue Error => e
    raise unless e.code == 'session_not_found'
  end

  # The engine's unauthenticated liveness check: :ok, :database_down (engine up, its database not) or :unhealthy.
  # Network failures (refused, timeout, DNS) raise, so the caller can tell "not answering" from "answering badly".
  def health
    response = HTTParty.get("#{ENV.fetch('WADESK_ENGINE_URL')}/health", timeout: HEALTH_TIMEOUT_SECONDS)
    body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return :ok if response.success? && body['status'] == 'ok'

    body['database'] == 'down' ? :database_down : :unhealthy
  end

  private

  def request(method, path, body = nil)
    headers = auth_headers
    # The engine rejects a JSON content type without a body (GET/DELETE).
    headers['Content-Type'] = 'application/json' if body
    response = HTTParty.public_send(method, "#{ENV.fetch('WADESK_ENGINE_URL')}#{path}",
                                    headers: headers, body: body&.to_json, timeout: TIMEOUT_SECONDS)
    return response.parsed_response if response.success?

    raise_error(response)
  end

  def auth_headers
    { 'Authorization' => "Bearer #{ENV.fetch('WADESK_ENGINE_API_TOKEN')}" }
  end

  def raise_error(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response.fetch('error', {}) : {}
    raise Error.new(response.code, error['code'], error['message'] || response.body)
  end

  # Chatwoot's base URL as reachable from the engine (internal network), defaulting to FRONTEND_URL.
  def callback_base_url
    ENV.fetch('WADESK_ENGINE_CALLBACK_BASE_URL') { ENV.fetch('FRONTEND_URL') }
  end
end
