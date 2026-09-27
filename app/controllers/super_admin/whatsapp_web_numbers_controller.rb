# WaDesk: every WhatsApp Web number across client accounts with its stored connection state (WW-FR-31).
class SuperAdmin::WhatsappWebNumbersController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  FILTERS = { 'attention' => 'Need attention', 'connected' => 'Connected', 'all' => 'All' }.freeze
  # Sorts false (needs attention) before true (connected).
  CONNECTED_SQL = "channel_whatsapp.provider_config->>'connection_state' IS NOT DISTINCT FROM 'connected'".freeze

  def index
    @filter = FILTERS.key?(params[:filter]) ? params[:filter] : 'attention'
    @search = params[:search].to_s.strip
    @counts = { 'attention' => numbers_needing_attention_count, 'connected' => Channel::Whatsapp.whatsapp_web_connected.count,
                'all' => Channel::Whatsapp.whatsapp_web.count }
    @numbers = searched(filtered).includes(:inbox, :account).order(Arel.sql(CONNECTED_SQL), :account_id, :id)
                                 .page(params[:page]).per(50).load
  end

  private

  def filtered
    { 'attention' => Channel::Whatsapp.whatsapp_web_needing_attention, 'connected' => Channel::Whatsapp.whatsapp_web_connected }
      .fetch(@filter, Channel::Whatsapp.whatsapp_web)
  end

  # Matches part of the number however it is typed (numbers are stored as + and digits), or of the client or inbox name.
  def searched(numbers)
    return numbers if @search.blank?

    name = "%#{Channel::Whatsapp.sanitize_sql_like(@search)}%"
    digits = @search.gsub(/\D/, '')
    conditions = ['accounts.name ILIKE :name', 'inboxes.name ILIKE :name']
    conditions << 'channel_whatsapp.phone_number LIKE :digits' if digits.present?
    numbers.joins(:account, :inbox).where(conditions.join(' OR '), name: name, digits: "%#{digits}%")
  end
end
