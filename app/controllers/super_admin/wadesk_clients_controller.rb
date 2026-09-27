# WaDesk: the operator console's Clients pages (ADR-0008). The operator manages each client's plan (WhatsApp Official /
# WhatsApp Web), the daily new-chat limit of its WhatsApp Web numbers, and which Chatwoot features its app shows
# (Wadesk::ClientFeatures). Turning a plan off only blocks new inboxes of that type; existing ones keep working.
class SuperAdmin::WadeskClientsController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  PLAN_FEATURES = { 'whatsapp_official' => 'WhatsApp Official', 'whatsapp_web' => 'WhatsApp Web' }.freeze
  PLAN_FILTERS = { 'all' => 'All', 'both' => 'Both', 'web' => 'Web only', 'official' => 'Official only' }.freeze
  DAILY_NEW_CHATS_RANGE = (1..1000)
  LIMIT_KEY = Wadesk::Safety::NewChatLimit::LIMIT_KEY

  before_action :set_account, only: [:edit, :update]

  def index
    @search = params[:search].to_s.strip
    @plan_filter = PLAN_FILTERS.key?(params[:plan]) ? params[:plan] : 'all'
    clients = searched_accounts
    @plan_counts = PLAN_FILTERS.keys.index_with { |filter| filter_by_plan(clients, filter).count }
    @accounts = filter_by_plan(clients, @plan_filter).order(:id).page(params[:page]).per(25)
    @inbox_counts = whatsapp_inbox_counts(@accounts.map(&:id))
  end

  def edit
    @daily_new_chats = @account.custom_attributes[LIMIT_KEY]
    @selected_plans = PLAN_FEATURES.keys.select { |feature| @account.feature_enabled?(feature) }
    @selected_features = Wadesk::ClientFeatures::NAMES.select { |feature| @account.feature_enabled?(feature) }
    load_client_page
  end

  def update
    @daily_new_chats = client_params[:daily_new_chats]
    return render_invalid_limit unless valid_daily_new_chats?

    kept_inboxes = plans_turned_off_with_inboxes
    turned_off = features_turned_off
    PLAN_FEATURES.each_key { |feature| plan_selected?(feature) ? @account.enable_features(feature) : @account.disable_features(feature) }
    submitted_features.each { |feature, on| on ? @account.enable_features(feature) : @account.disable_features(feature) }
    @account.custom_attributes = updated_custom_attributes
    @account.save!

    redirect_to edit_super_admin_wadesk_client_path(@account), notice: update_notice(kept_inboxes, turned_off)
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  # Only allow-listed feature flags pass; anything else (e.g. captain_integration) is dropped here.
  def client_params
    params.require(:client).permit(:daily_new_chats, *PLAN_FEATURES.keys, features: Wadesk::ClientFeatures::NAMES)
  end

  def plan_selected?(feature)
    client_params[feature] == '1'
  end

  # Allow-listed features the form sent, as name => on?. A feature the form did not send stays as it is.
  def submitted_features
    features = client_params[:features] || {}
    Wadesk::ClientFeatures::NAMES.filter_map { |name| [name, features[name] == '1'] if features.key?(name) }.to_h
  end

  def features_turned_off
    submitted_features.filter_map { |feature, on| feature if !on && @account.feature_enabled?(feature) }
  end

  def searched_accounts
    return Account.all if @search.blank?

    Account.where('name ILIKE :name OR id::text = :id', name: "%#{Account.sanitize_sql_like(@search)}%", id: @search)
  end

  def filter_by_plan(accounts, filter)
    case filter
    when 'both' then accounts.feature_whatsapp_official.feature_whatsapp_web
    when 'web' then accounts.feature_whatsapp_web.not_feature_whatsapp_official
    when 'official' then accounts.feature_whatsapp_official.not_feature_whatsapp_web
    else accounts
    end
  end

  def load_client_page
    @inbox_counts = whatsapp_inbox_counts([@account.id])
    @numbers = Channel::Whatsapp.whatsapp_web.where(account_id: @account.id).includes(:inbox).order(:id)
    @agents_count = @account.account_users.count
  end

  # Blank goes back to the default; anything else must be a whole number in range.
  def valid_daily_new_chats?
    @daily_new_chats.blank? || (@daily_new_chats.match?(/\A\d+\z/) && DAILY_NEW_CHATS_RANGE.cover?(@daily_new_chats.to_i))
  end

  # Re-shows the form with what the operator entered, so a rejected limit does not silently undo their other choices.
  def render_invalid_limit
    @selected_plans = PLAN_FEATURES.keys.select { |feature| plan_selected?(feature) }
    submitted = submitted_features
    @selected_features = Wadesk::ClientFeatures::NAMES.select { |feature| submitted.fetch(feature) { @account.feature_enabled?(feature) } }
    @limit_invalid = true
    load_client_page
    flash.now[:error] = "Daily new-chat limit must be a whole number from #{DAILY_NEW_CHATS_RANGE.min} to #{DAILY_NEW_CHATS_RANGE.max}, " \
                        "or blank for the default (#{Wadesk::Safety::NewChatLimit::DEFAULT_DAILY_LIMIT})."
    render :edit, status: :unprocessable_entity
  end

  def updated_custom_attributes
    attributes = @account.custom_attributes.except(LIMIT_KEY)
    @daily_new_chats.blank? ? attributes : attributes.merge(LIMIT_KEY => @daily_new_chats.to_i)
  end

  # Plans being turned off while the account still has inboxes of that type.
  def plans_turned_off_with_inboxes
    counts = whatsapp_inbox_counts([@account.id])
    PLAN_FEATURES.keys.select do |feature|
      @account.feature_enabled?(feature) && !plan_selected?(feature) && counts[feature][@account.id].to_i.positive?
    end
  end

  def update_notice(kept_inboxes, turned_off)
    notice = "Plan for #{@account.name} updated."
    if kept_inboxes.any?
      notice += " Existing #{kept_inboxes.map { |feature| PLAN_FEATURES[feature] }.to_sentence} inboxes keep working; only new ones are blocked."
    end
    return notice if turned_off.empty?

    "#{notice} Hidden from the client's app: #{turned_off.map { |feature| Wadesk::ClientFeatures.fetch(feature).label }.to_sentence}."
  end

  # Counts per account id, keyed by plan feature, plus WhatsApp Web numbers needing attention. Every channel has exactly one inbox.
  def whatsapp_inbox_counts(account_ids)
    whatsapp = Channel::Whatsapp.where(account_id: account_ids)
    official = whatsapp.where.not(provider: 'baileys').group(:account_id).count
    twilio = Channel::TwilioSms.whatsapp.where(account_id: account_ids).group(:account_id).count
    {
      'whatsapp_official' => official.merge(twilio) { |_id, cloud, twilio_count| cloud + twilio_count },
      'whatsapp_web' => whatsapp.whatsapp_web.group(:account_id).count,
      'attention' => whatsapp.whatsapp_web_needing_attention.group(:account_id).count
    }
  end
end
