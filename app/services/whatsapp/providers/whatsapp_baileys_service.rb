# WaDesk: WhatsApp Web provider. Linking and messaging go through the internal wadesk-engine.
class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  LINK_METHODS = %w[qr code].freeze
  AGENT_ERRORS = {
    'not_connected' => 'WhatsApp Web is not connected. Reconnect the number in the inbox settings and send again.',
    'invalid_recipient' => 'This contact has no WhatsApp number this inbox can message.',
    'file_too_large' => 'The file is larger than WhatsApp allows (100 MB).'
  }.freeze

  # Sends through the engine (WW-FR-20/21/22). Rate limits and engine trouble raise, so the send job retries
  # later (queued, never dropped: SAFE-FR-03); anything else fails the message with a reason agents can act on.
  def send_message(phone_number, message)
    WhatsappWeb::EngineClient.new.send_message(whatsapp_channel.id, message_parts(phone_number, message))
  rescue WhatsappWeb::EngineClient::Error => e
    raise if e.retryable?

    message.update!(status: :failed, external_error: AGENT_ERRORS.fetch(e.code, e.message))
    nil
  end

  # No credentials to verify: the number is linked later by QR code or pairing code.
  def validate_provider_config?
    LINK_METHODS.include?(whatsapp_channel.provider_config['link_method'])
  end

  # Incoming media is downloaded from the engine, which fetches and decrypts it from WhatsApp.
  def media_url(media_id)
    "#{ENV.fetch('WADESK_ENGINE_URL')}/sessions/#{whatsapp_channel.id}/media/#{media_id}"
  end

  def api_headers
    { 'Authorization' => "Bearer #{ENV.fetch('WADESK_ENGINE_API_TOKEN')}" }
  end

  # WhatsApp Web has no message templates. Marking the sync keeps these channels from being
  # picked again by the template sync scheduler ahead of Cloud channels.
  def sync_templates
    whatsapp_channel.mark_message_templates_updated
  end

  private

  # Like the Cloud provider, only the first attachment is sent; the text becomes its caption.
  def message_parts(phone_number, message)
    { to: phone_number, text: message.outgoing_content.presence, file: attachment_part(message.attachments.first) }
      .merge(reply_parts(message))
  end

  def attachment_part(attachment)
    return if attachment.blank?

    blob = attachment.file.blob
    # Recordings stored as audio/opus are Ogg Opus; sent as audio/ogg they arrive as voice notes.
    content_type = blob.content_type == 'audio/opus' ? 'audio/ogg' : blob.content_type
    WhatsappWeb::EngineClient::UploadPart.new(StringIO.new(blob.download), blob.filename.to_s, content_type)
  end

  # The quoted message's text is sent along so the customer sees a preview of what is being answered.
  def reply_parts(message)
    external_id = message.content_attributes[:in_reply_to_external_id]
    return {} if external_id.blank?

    quoted = message.conversation.messages.find_by(source_id: external_id)
    { reply_to_id: external_id, reply_to_text: quoted&.content.to_s, reply_to_from_me: (quoted.present? && !quoted.incoming?).to_s }
  end
end
