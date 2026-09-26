# WaDesk: stores the engine's connection state on a WhatsApp Web channel (WW-FR-05, WW-FR-08).
class WhatsappWeb::ConnectionUpdateService
  STATES = %w[connecting qr_pending connected disconnected logged_out failed].freeze
  # Losses the admin must act on (WW-FR-08). Brief drops reconnect on their own; an admin logout is deliberate.
  ALERT_REASONS = %w[unlinked_from_phone forbidden].freeze

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
    update_reauthorization(state, payload['reason'])
  end

  private

  # Reuses Chatwoot's reauthorization flow: emails administrators and flags the inbox in the sidebar.
  def update_reauthorization(state, reason)
    if state == 'connected'
      channel.reauthorized!
    elsif ALERT_REASONS.include?(reason)
      channel.prompt_reauthorization!
    end
  end
end
