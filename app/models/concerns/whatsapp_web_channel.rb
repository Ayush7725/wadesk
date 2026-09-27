# WaDesk: WhatsApp Web inboxes are Channel::Whatsapp records with provider "baileys",
# served by the internal wadesk-engine (docs/wadesk/adr/0003-baileys-as-chatwoot-provider.md).
module WhatsappWebChannel
  extend ActiveSupport::Concern

  included do
    scope :whatsapp_web, -> { where(provider: 'baileys') }
    # Missing state means the number was never linked, so it counts as needing attention.
    scope :whatsapp_web_connected, -> { whatsapp_web.where("channel_whatsapp.provider_config->>'connection_state' = 'connected'") }
    scope :whatsapp_web_needing_attention, lambda {
      whatsapp_web.where("channel_whatsapp.provider_config->>'connection_state' IS DISTINCT FROM 'connected'")
    }
    before_validation :default_whatsapp_web_link_method, if: :whatsapp_web?
    validate :whatsapp_web_enabled_for_account, if: -> { whatsapp_web? && (new_record? || will_save_change_to_provider?) }
    after_commit :start_whatsapp_web_session, on: :create, if: :whatsapp_web?
    before_destroy :remove_whatsapp_web_session, if: :whatsapp_web?
  end

  def whatsapp_web?
    provider == 'baileys'
  end

  private

  def default_whatsapp_web_link_method
    provider_config['link_method'] ||= 'qr'
  end

  # Plan gating at the model, so every creation path is covered (ADR-0005), including switching an existing inbox to
  # WhatsApp Web. Existing inboxes keep working if the feature is later disabled; suspension is defined with billing.
  def whatsapp_web_enabled_for_account
    errors.add(:provider, 'WhatsApp Web is not enabled for this account') unless account.feature_enabled?('whatsapp_web')
  end

  def start_whatsapp_web_session
    WhatsappWeb::StartSessionJob.perform_later(self)
  end

  # Logs the device out of WhatsApp and wipes its credentials in the engine (WW-FR-07).
  def remove_whatsapp_web_session
    WhatsappWeb::EngineClient.new.delete_session(id)
  end
end
