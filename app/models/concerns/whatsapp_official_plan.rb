# WaDesk: Official WhatsApp (Meta Cloud API, 360dialog and Twilio WhatsApp) is sold as a plan, like WhatsApp Web.
# Checked at the model when an inbox is created or switched to an Official type, so every path is covered and the
# plan cannot be bypassed by editing an existing inbox; other updates never re-check it, so turning the plan off does
# not break existing inboxes. Including models define whatsapp_official? and whatsapp_type_changing?.
module WhatsappOfficialPlan
  extend ActiveSupport::Concern

  included do
    validate :whatsapp_official_enabled_for_account, if: -> { whatsapp_official? && (new_record? || whatsapp_type_changing?) }
  end

  private

  def whatsapp_official_enabled_for_account
    errors.add(:base, 'WhatsApp Official is not enabled for this account') unless account.feature_enabled?('whatsapp_official')
  end
end
