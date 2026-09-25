# WaDesk: WhatsApp Web inboxes are conversations-only; campaigns need the Official API (ADR-0006, SAFE-FR-01).
module WhatsappWebCampaignGuard
  extend ActiveSupport::Concern

  included do
    validate :reject_whatsapp_web_inbox
  end

  private

  def reject_whatsapp_web_inbox
    return unless inbox&.channel.is_a?(Channel::Whatsapp) && inbox.channel.whatsapp_web?

    errors.add(:inbox, 'Campaigns are not available for WhatsApp Web inboxes. Use an Official WhatsApp inbox for campaigns.')
  end
end
