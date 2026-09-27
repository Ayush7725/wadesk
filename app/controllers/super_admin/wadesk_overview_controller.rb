# WaDesk: home page of the operator console. Every figure is a SQL count; only the listed numbers are loaded.
class SuperAdmin::WadeskOverviewController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  ATTENTION_LIST_SIZE = 8
  PLANS = [['Both', true, true], ['Web only', true, false], ['Official only', false, true], ['No WhatsApp', false, false]].freeze

  def show
    @clients = Account.group(:status).count
    @numbers = whatsapp_web_totals
    @needing_attention = Channel::Whatsapp.whatsapp_web_needing_attention.includes(:inbox, :account)
                                          .order(:account_id, :id).limit(ATTENTION_LIST_SIZE)
    @plans = plan_counts
  end

  private

  def whatsapp_web_totals
    numbers = Channel::Whatsapp.whatsapp_web
    { total: numbers.count, clients: numbers.distinct.count(:account_id), connected: Channel::Whatsapp.whatsapp_web_connected.count }
  end

  # Clients per plan in one grouped query. Plan flags live in a bitmask column (Featurable / FlagShihTzu).
  def plan_counts
    counts = Account.group(Arel.sql(plan_flag_sql('whatsapp_web')), Arel.sql(plan_flag_sql('whatsapp_official'))).count
    PLANS.map { |label, web, official| [label, counts[[web, official]].to_i] }
  end

  def plan_flag_sql(feature)
    column = Featurable::FEATURE_LIST.find { |flag| flag['name'] == feature }['column'] || Featurable::DEFAULT_FEATURE_FLAG_COLUMN
    bit = Account.flag_mapping.fetch(column).fetch(:"feature_#{feature}")
    "(accounts.#{column} & #{bit}) <> 0"
  end
end
