# WaDesk: what the operator console may change about a user's access (CR-004), with the guards that keep an installation
# manageable: every client keeps at least one administrator, and there is always at least one operator (a Chatwoot
# super admin, users.type = 'SuperAdmin'), who can never remove their own operator access. Adding a user to a client goes
# through Chatwoot's AgentBuilder, the same path as inviting an agent from the client's own settings.
class Wadesk::UserAccess
  class Refused < StandardError; end

  ROLES = { 'administrator' => 'Admin', 'agent' => 'Agent' }.freeze

  pattr_initialize [:user!, :operator!]

  def add_to_client!(account, role)
    raise Refused, 'Choose Administrator or Agent.' unless ROLES.key?(role)
    raise Refused, "#{user.name} already belongs to #{account.name}." if user.account_users.exists?(account_id: account.id)

    AgentBuilder.new(email: user.email, name: user.name, inviter: operator, account: account, role: role).perform
  rescue AgentBuilder::LimitExceededError, CustomExceptions::Account::EmailLimitExceeded, ActiveRecord::RecordInvalid => e
    raise Refused, e.message
  end

  def remove_from_client!(account_user)
    AccountUser.transaction do
      administrators = account_user.account.account_users.administrator.lock.pluck(:id)
      raise Refused, last_administrator_message(account_user.account) if administrators == [account_user.id]

      account_user.destroy!
    end
  end

  def make_operator!
    user.update!(type: 'SuperAdmin') unless operator?(user)
  end

  def remove_operator!
    return unless operator?(user)

    User.transaction do
      others = SuperAdmin.where.not(id: user.id).lock.pluck(:id)
      raise Refused, 'There must always be at least one operator. Make someone else an operator first.' if others.empty?
      raise Refused, 'You can\'t remove your own operator access. Ask another operator to do it.' if user.id == operator.id

      user.update!(type: nil)
    end
  end

  def self.last_administrator?(account_user, administrator_counts)
    account_user.administrator? && administrator_counts[account_user.account_id].to_i <= 1
  end

  private

  def operator?(record)
    record.type == 'SuperAdmin'
  end

  def last_administrator_message(account)
    "#{user.name} is the only administrator of #{account.name}. A client always needs an administrator to manage its " \
      'inboxes, agents and settings, so add another administrator first.'
  end
end
