# WaDesk: the operator manages each client's plan (WhatsApp Official / WhatsApp Web) and the daily new-chat limit
# of its WhatsApp Web numbers. Turning a plan off only blocks new inboxes of that type; existing ones keep working.
class SuperAdmin::WadeskClientsController < SuperAdmin::ApplicationController
  PLAN_FEATURES = { 'whatsapp_official' => 'WhatsApp Official', 'whatsapp_web' => 'WhatsApp Web' }.freeze
  DAILY_NEW_CHATS_RANGE = (1..1000)
  LIMIT_KEY = Wadesk::Safety::NewChatLimit::LIMIT_KEY

  before_action :set_account, only: [:edit, :update]

  def index
    @search = params[:search].to_s.strip
    @accounts = Account.order(:id).page(params[:page]).per(25)
    if @search.present?
      @accounts = @accounts.where('name ILIKE :name OR id::text = :id', name: "%#{Account.sanitize_sql_like(@search)}%", id: @search)
    end
    @inbox_counts = whatsapp_inbox_counts(@accounts.map(&:id))
  end

  def edit
    @daily_new_chats = @account.custom_attributes[LIMIT_KEY]
    @selected_plans = PLAN_FEATURES.keys.select { |feature| @account.feature_enabled?(feature) }
    @inbox_counts = whatsapp_inbox_counts([@account.id])
  end

  def update
    @daily_new_chats = client_params[:daily_new_chats]
    return render_invalid_limit unless valid_daily_new_chats?

    kept_inboxes = plans_turned_off_with_inboxes
    PLAN_FEATURES.each_key { |feature| plan_selected?(feature) ? @account.enable_features(feature) : @account.disable_features(feature) }
    @account.custom_attributes = updated_custom_attributes
    @account.save!

    redirect_to super_admin_wadesk_clients_path, notice: update_notice(kept_inboxes)
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:daily_new_chats, *PLAN_FEATURES.keys)
  end

  def plan_selected?(feature)
    client_params[feature] == '1'
  end

  # Blank goes back to the default; anything else must be a whole number in range.
  def valid_daily_new_chats?
    @daily_new_chats.blank? || (@daily_new_chats.match?(/\A\d+\z/) && DAILY_NEW_CHATS_RANGE.cover?(@daily_new_chats.to_i))
  end

  # Re-shows the form with what the operator entered, so a rejected limit does not silently undo their plan choices.
  def render_invalid_limit
    @selected_plans = PLAN_FEATURES.keys.select { |feature| plan_selected?(feature) }
    @inbox_counts = whatsapp_inbox_counts([@account.id])
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

  def update_notice(kept_inboxes)
    notice = "Plan for #{@account.name} updated."
    return notice if kept_inboxes.empty?

    "#{notice} Existing #{kept_inboxes.map { |feature| PLAN_FEATURES[feature] }.to_sentence} inboxes keep working; only new ones are blocked."
  end

  # Counts per account id, keyed by plan feature. Every channel has exactly one inbox.
  def whatsapp_inbox_counts(account_ids)
    whatsapp = Channel::Whatsapp.where(account_id: account_ids)
    official = whatsapp.where.not(provider: 'baileys').group(:account_id).count
    twilio = Channel::TwilioSms.whatsapp.where(account_id: account_ids).group(:account_id).count
    {
      'whatsapp_official' => official.merge(twilio) { |_id, cloud, twilio_count| cloud + twilio_count },
      'whatsapp_web' => whatsapp.where(provider: 'baileys').group(:account_id).count
    }
  end
end
