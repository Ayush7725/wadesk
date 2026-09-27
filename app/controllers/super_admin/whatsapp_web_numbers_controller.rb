# WaDesk: lists every WhatsApp Web number across client accounts with its stored connection state (WW-FR-31).
class SuperAdmin::WhatsappWebNumbersController < SuperAdmin::ApplicationController
  CONNECTED_SQL = "channel_whatsapp.provider_config->>'connection_state' IS NOT DISTINCT FROM 'connected'".freeze
  STATE_LABELS = {
    'connected' => 'Connected', 'connecting' => 'Connecting', 'qr_pending' => 'Waiting for scan',
    'disconnected' => 'Disconnected', 'logged_out' => 'Logged out', 'failed' => 'Could not link'
  }.freeze
  REASON_LABELS = {
    'unlinked_from_phone' => 'Removed from the phone\'s Linked devices', 'logged_out_by_admin' => 'Logged out by an inbox administrator',
    'number_mismatch' => 'A phone with a different number was linked', 'qr_expired' => 'Nobody linked the phone in time',
    'connection_lost' => 'Connection to WhatsApp lost', 'forbidden' => 'WhatsApp refused the connection'
  }.freeze

  helper_method :state_label, :reason_label

  def index
    numbers = Channel::Whatsapp.where(provider: 'baileys')
    @summary = { total: numbers.count, connected: numbers.where(CONNECTED_SQL).count }
    @filter = %w[attention connected].include?(params[:filter]) ? params[:filter] : 'all'
    numbers = numbers.where(CONNECTED_SQL) if @filter == 'connected'
    numbers = numbers.where.not(CONNECTED_SQL) if @filter == 'attention'
    @numbers = numbers.includes(:inbox, :account).order(Arel.sql(CONNECTED_SQL), :account_id, :id).page(params[:page]).per(50)
  end

  private

  def state_label(state)
    STATE_LABELS.fetch(state, 'Never linked')
  end

  def reason_label(reason)
    REASON_LABELS.fetch(reason, reason.to_s.humanize)
  end
end
