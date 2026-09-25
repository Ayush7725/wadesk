# WaDesk: WhatsApp Web provider. Linking and messaging go through the internal wadesk-engine.
class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  LINK_METHODS = %w[qr code].freeze

  # No credentials to verify: the number is linked later by QR code or pairing code.
  def validate_provider_config?
    LINK_METHODS.include?(whatsapp_channel.provider_config['link_method'])
  end

  # WhatsApp Web has no message templates. Marking the sync keeps these channels from being
  # picked again by the template sync scheduler ahead of Cloud channels.
  def sync_templates
    whatsapp_channel.mark_message_templates_updated
  end
end
