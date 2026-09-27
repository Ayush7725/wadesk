# WaDesk: Official WhatsApp (Meta Cloud API, 360dialog and Twilio WhatsApp) is sold as a plan, like WhatsApp Web.
# Checked at the model on create only, so every creation path is covered and turning the plan off never breaks
# existing inboxes. Including models define whatsapp_official?.
module WhatsappOfficialPlan
  extend ActiveSupport::Concern

  included do
    validate :whatsapp_official_enabled_for_account, on: :create, if: :whatsapp_official?
  end

  private

  def whatsapp_official_enabled_for_account
    errors.add(:base, 'WhatsApp Official is not enabled for this account') unless account.feature_enabled?('whatsapp_official')
  end
end
