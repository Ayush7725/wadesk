# WaDesk: navigation of the operator console (ADR-0008).
module SuperAdmin::WadeskConsoleHelper
  def console_nav_links
    [
      { label: 'Overview', url: super_admin_root_path, icon: 'icon-grid-line', active: controller_name == 'wadesk_overview' },
      { label: 'Clients', url: super_admin_wadesk_clients_path, icon: 'icon-chat-smile-3-line', active: controller_name == 'wadesk_clients' },
      { label: 'WhatsApp numbers', url: super_admin_whatsapp_web_numbers_path, icon: 'icon-whatsapp-line',
        active: controller_name == 'whatsapp_web_numbers', badge: numbers_needing_attention_count }
    ]
  end

  # Chatwoot's own Super Admin pages, unchanged.
  def console_advanced_links
    [
      { label: 'Chatwoot admin', url: super_admin_chatwoot_dashboard_path, icon: 'icon-gear', active: false },
      { label: 'System health', url: super_admin_instance_status_path, icon: 'icon-health-book-line', active: false },
      { label: 'Background jobs', url: sidekiq_web_path, icon: 'icon-mist-fill', active: false }
    ]
  end
end
