# WaDesk: suspends and reactivates a client from the operator console, in Chatwoot's own terms: the account's status
# (active / suspended) and the suspension history Chatwoot's Super Admin keeps in internal_attributes['suspensions']
# (see SuperAdmin::AccountsController#apply_suspension_metadata). Each suspension adds an event with the same keys and
# rules (category from Account::SUSPENSION_CATEGORIES, reason up to 256 characters, suspended_at, suspended_by), so
# Chatwoot's admin shows it in the account's suspension history. Reactivating keeps the history, as Chatwoot does.
class Wadesk::ClientSuspension
  include ActiveModel::Model
  include ActiveModel::Attributes

  REASON_MAX = 256

  attribute :category, :string
  attribute :reason, :string

  validates :category, presence: true
  validates :category, inclusion: { in: Account::SUSPENSION_CATEGORIES }, allow_blank: true
  validates :reason, presence: true, length: { maximum: REASON_MAX }

  def self.human_attribute_name(attribute, options = {})
    { category: 'Category', reason: 'Reason' }.fetch(attribute.to_sym) { super }
  end

  def self.reactivate(account)
    account.update!(status: :active)
  end

  # Chatwoot's category labels (Spam, Non-payment, Other), for the form and the client page.
  def self.category_label(category)
    I18n.t("super_admin.account_suspension.categories.#{category}", default: category.to_s.humanize)
  end

  def suspend(account, operator)
    self.reason = reason.to_s.strip
    return false unless valid?

    event = { 'category' => category, 'reason' => reason, 'suspended_at' => Time.current.iso8601, 'suspended_by' => operator.id }
    account.update!(status: :suspended, internal_attributes: account.internal_attributes.merge('suspensions' => account.suspension_history + [event]))
  end
end
