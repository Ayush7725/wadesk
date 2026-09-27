# WaDesk: the operator console's Users pages (CR-004): everyone who can log in to a client's WaDesk or to this console.
# The operator adds and removes users from clients, resends invitations, sets passwords and grants operator access, so
# Chatwoot's own /super_admin/users pages are never needed. Access rules (last administrator, last operator) live in
# Wadesk::UserAccess. Memberships are member routes of this controller so Administrate's navigation does not list them.
class SuperAdmin::WadeskUsersController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  FILTERS = { 'all' => 'All', 'operators' => 'Operators', 'unconfirmed' => 'Unconfirmed' }.freeze

  before_action :set_user, except: [:index, :new, :create]

  def index
    @search = params[:search].to_s.strip
    @filter = FILTERS.key?(params[:filter]) ? params[:filter] : 'all'
    users = searched_users
    @counts = FILTERS.keys.index_with { |filter| filter_users(users, filter).count }
    @users = filter_users(users, @filter).includes(account_users: :account).order(Arel.sql('lower(users.name)'), :id)
                                         .page(params[:page]).per(25)
  end

  def show
    load_user_page
  end

  def new
    @new_user = { 'role' => 'administrator' }
    @clients = Account.order(:name, :id)
  end

  def create
    @new_user = new_user_params.to_h
    existing = User.from_email(@new_user['email'].to_s.strip)
    return render_new_user_error('A user with this email already exists. Open their page to add them to a client.', existing) if existing

    account = Account.find_by(id: @new_user['account_id'])
    return render_new_user_error('Choose the client this user belongs to.') unless account
    return render_new_user_error('Choose Administrator or Agent.') unless Wadesk::UserAccess::ROLES.key?(@new_user['role'])

    user = invite(account)
    redirect_to super_admin_wadesk_user_path(user), notice: "#{user.name} was added to #{account.name}. An invitation was sent to #{user.email}."
  rescue AgentBuilder::LimitExceededError, CustomExceptions::Account::EmailLimitExceeded, ActiveRecord::RecordInvalid => e
    render_new_user_error(e.message)
  end

  def resend_confirmation
    return redirect_to(super_admin_wadesk_user_path(@user), alert: "#{@user.name} has already accepted the invitation.") if @user.confirmed?

    @user.send_confirmation_instructions
    redirect_to super_admin_wadesk_user_path(@user), notice: "Invitation sent again to #{@user.email}."
  end

  def confirm
    return redirect_to(super_admin_wadesk_user_path(@user), alert: "#{@user.email} is already confirmed.") if @user.confirmed?

    @user.skip_reconfirmation!
    @user.confirm
    redirect_to super_admin_wadesk_user_path(@user), notice: "#{@user.email} is confirmed. #{@user.name} can log in with their password."
  end

  def password
    passwords = params.require(:user).permit(:password, :password_confirmation)
    if @user.update(passwords)
      redirect_to super_admin_wadesk_user_path(@user), notice: "New password saved. #{@user.name} can log in with it now."
    else
      # The strength rules are also reported for the confirmation field; show them once.
      @password_errors = @user.errors.reject { |error| error.attribute == :password_confirmation && error.type != :confirmation }.map(&:full_message)
      @user = User.find(@user.id)
      load_user_page
      render :show, status: :unprocessable_content
    end
  end

  def operator
    if params[:operator] == '1'
      user_access.make_operator!
      redirect_to super_admin_wadesk_user_path(@user), notice: "#{@user.name} is now an operator and can open this console."
    else
      user_access.remove_operator!
      redirect_to super_admin_wadesk_user_path(@user), notice: "#{@user.name} is no longer an operator."
    end
  rescue Wadesk::UserAccess::Refused => e
    redirect_to super_admin_wadesk_user_path(@user), alert: e.message
  end

  def add_membership
    membership = params.require(:membership).permit(:account_id, :role)
    account = Account.find(membership[:account_id])
    user_access.add_to_client!(account, membership[:role].to_s)
    redirect_to super_admin_wadesk_user_path(@user),
                notice: "#{@user.name} was added to #{account.name} as #{Wadesk::UserAccess::ROLES[membership[:role]]}."
  rescue Wadesk::UserAccess::Refused => e
    redirect_to super_admin_wadesk_user_path(@user), alert: e.message
  end

  def remove_membership
    account_user = @user.account_users.find(params[:membership_id])
    user_access.remove_from_client!(account_user)
    redirect_to super_admin_wadesk_user_path(@user), notice: "#{@user.name} was removed from #{account_user.account.name}."
  rescue Wadesk::UserAccess::Refused => e
    redirect_to super_admin_wadesk_user_path(@user), alert: e.message
  end

  private

  def user_access
    Wadesk::UserAccess.new(user: @user, operator: current_super_admin)
  end

  def set_user
    @user = User.find(params[:id])
  end

  def searched_users
    return User.all if @search.blank?

    User.where('users.name ILIKE :term OR users.email ILIKE :term', term: "%#{User.sanitize_sql_like(@search)}%")
  end

  def filter_users(users, filter)
    case filter
    when 'operators' then users.where(type: 'SuperAdmin')
    when 'unconfirmed' then users.where(confirmed_at: nil)
    else users
    end
  end

  def load_user_page
    @memberships = @user.account_users.includes(:account).sort_by { |account_user| [account_user.account.name.downcase, account_user.id] }
    @administrator_counts = AccountUser.administrator.where(account_id: @memberships.map(&:account_id)).group(:account_id).count
    @available_clients = Account.where.not(id: @memberships.map(&:account_id)).order(:name, :id)
    @operator_count = SuperAdmin.count
  end

  def new_user_params
    params.require(:user).permit(:name, :email, :account_id, :role)
  end

  def invite(account)
    AgentBuilder.new(email: @new_user['email'].to_s.strip, name: @new_user['name'].to_s.strip, inviter: current_super_admin,
                     account: account, role: @new_user['role']).perform
  end

  def render_new_user_error(message, existing_user = nil)
    @error = message
    @existing_user = existing_user
    @clients = Account.order(:name, :id)
    render :new, status: :unprocessable_content
  end
end
