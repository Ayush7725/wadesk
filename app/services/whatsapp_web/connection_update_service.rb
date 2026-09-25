# WaDesk: stores the engine's connection state on a WhatsApp Web channel (WW-FR-05, WW-FR-08).
class WhatsappWeb::ConnectionUpdateService
  STATES = %w[connecting qr_pending connected disconnected logged_out failed].freeze

  pattr_initialize [:channel!, :payload!]

  def perform
    state = payload.fetch('state')
    raise ArgumentError, "Unknown WhatsApp Web connection state: #{state}" unless STATES.include?(state)

    channel.update!(provider_config: channel.provider_config.merge(
      'connection_state' => state,
      'connection_reason' => payload['reason'],
      'connected_phone' => payload.dig('me', 'phone'),
      'connection_updated_at' => Time.zone.now.iso8601
    ))
  end
end
