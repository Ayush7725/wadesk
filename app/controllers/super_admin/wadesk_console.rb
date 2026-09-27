# WaDesk: shared by the operator console pages (ADR-0008): console layout and the sidebar's attention count.
module SuperAdmin::WadeskConsole
  extend ActiveSupport::Concern

  included do
    layout 'super_admin/wadesk_console'
    helper SuperAdmin::WadeskConsoleHelper
    helper_method :numbers_needing_attention_count
  end

  private

  def numbers_needing_attention_count
    @numbers_needing_attention_count ||= Channel::Whatsapp.whatsapp_web_needing_attention.count
  end
end
