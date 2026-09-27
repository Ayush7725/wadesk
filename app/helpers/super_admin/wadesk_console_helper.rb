# WaDesk: navigation and shared pieces of the operator console (ADR-0008).
module SuperAdmin::WadeskConsoleHelper
  NUMBER_STATES = {
    'connected' => ['Connected', :ok], 'connecting' => ['Connecting', :warn], 'qr_pending' => ['Waiting for scan', :warn],
    'disconnected' => ['Reconnecting', :warn], 'logged_out' => ['Logged out', :bad], 'failed' => ['Could not link', :bad]
  }.freeze
  NUMBER_REASONS = {
    'unlinked_from_phone' => 'Removed from the phone\'s Linked devices', 'logged_out_by_admin' => 'Logged out by an inbox administrator',
    'number_mismatch' => 'A phone with a different number was linked', 'qr_expired' => 'Nobody linked the phone in time',
    'connection_lost' => 'Connection to WhatsApp lost', 'forbidden' => 'WhatsApp refused the connection'
  }.freeze
  PILL_TONES = {
    ok: 'bg-n-teal-3 text-n-teal-11', warn: 'bg-n-amber-3 text-n-amber-11', bad: 'bg-n-ruby-3 text-n-ruby-11', mute: 'bg-n-alpha-2 text-n-slate-11',
    info: 'bg-n-blue-3 text-n-blue-11'
  }.freeze

  # A small rounded status label with a dot, e.g. console_pill('Connected', :ok).
  def console_pill(label, tone)
    tag.span(class: "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium #{PILL_TONES.fetch(tone)}") do
      safe_join([tag.span(class: 'size-1.5 rounded-full bg-current', 'aria-hidden': true), label])
    end
  end

  # Label, tone and plain-words reason of a WhatsApp Web number's stored connection state; missing state = never linked.
  def whatsapp_web_state(channel)
    config = channel.provider_config
    label, tone = NUMBER_STATES.fetch(config['connection_state'], ['Never linked', :mute])
    reason = config['connection_reason'].presence
    { label: label, tone: tone, reason: reason && NUMBER_REASONS.fetch(reason, reason.humanize) }
  end

  def whatsapp_web_state_pill(channel)
    state = whatsapp_web_state(channel)
    console_pill(state[:label], state[:tone])
  end

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

  # What happened to a number, in plain words; falls back to what its state means when the engine gave no reason.
  def whatsapp_web_reason(channel)
    whatsapp_web_state(channel)[:reason] || {
      nil => 'Nobody has linked a phone yet', 'qr_pending' => 'Waiting for the phone to scan the code',
      'connecting' => 'Connecting to WhatsApp', 'disconnected' => 'Connection dropped; reconnecting on its own'
    }[channel.provider_config['connection_state']]
  end
end
