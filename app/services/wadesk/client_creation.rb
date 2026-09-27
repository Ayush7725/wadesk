# WaDesk: creates a client (a Chatwoot account) and its first administrator from the operator console's "New client" form.
# Reuses Chatwoot's own paths rather than its signup builder (AccountBuilder), which cannot invite a user:
# - the account is created like Super Admin's "New account" (Account.create!), so config/features.yml's default features
#   are turned on by Featurable's before_create;
# - the administrator is linked with AgentBuilder, Chatwoot's "invite an agent" path, as an administrator invited by the
#   operator. A new user gets Chatwoot's invitation email, whose link lets them set a password; a user who already has
#   a login (any client, or none) is only added to the new client, with no email and their password unchanged.
# - With "Set a password now", the user is first created confirmed with that password (as AccountBuilder does for a
#   confirmed signup), so AgentBuilder finds an existing, confirmed user and sends nothing.
# Name, email and password are checked by Chatwoot's User validations, so the rules match the rest of the app.
class Wadesk::ClientCreation
  include ActiveModel::Model
  include ActiveModel::Attributes

  LABELS = { name: 'Client name', admin_name: 'Admin name', admin_email: 'Admin email', admin_password: 'Password' }.freeze
  USER_FIELDS = { name: :admin_name, email: :admin_email, password: :admin_password }.freeze

  attribute :name, :string
  attribute :admin_name, :string
  attribute :admin_email, :string
  attribute :set_password, :boolean, default: false
  attribute :admin_password, :string

  attr_reader :account, :admin

  validates :name, presence: true
  validate :admin_is_valid

  def self.human_attribute_name(attribute, options = {})
    LABELS.fetch(attribute.to_sym) { super }
  end

  # The user who already has this email, if any; they become the administrator as they are.
  def existing_admin
    return @existing_admin if defined?(@existing_admin)

    @existing_admin = email.present? ? User.from_email(email) : nil
  end

  # true when Chatwoot's invitation email was sent to a new user.
  def invited?
    existing_admin.nil? && !set_password
  end

  def save(operator)
    return false unless valid?

    ActiveRecord::Base.transaction do
      @account = Account.create!(name: name.strip)
      create_user_with_password if set_password && existing_admin.nil?
      @admin = AgentBuilder.new(email: email, name: admin_name.to_s.strip, inviter: operator, account: @account, role: :administrator).perform
    end
    true
  end

  private

  def email
    admin_email.to_s.strip.downcase
  end

  def create_user_with_password
    user = new_admin_user
    user.skip_confirmation!
    user.save!
  end

  # An existing user is used as they are; otherwise the new user must pass Chatwoot's User validations. Without a password
  # now, a throwaway one stands in (AgentBuilder gives the invited user its own) so only name and email are checked.
  def admin_is_valid
    return if existing_admin

    user = new_admin_user
    user.valid?
    USER_FIELDS.each { |field, attribute| user.errors[field].uniq.each { |message| errors.add(attribute, message) } }
  end

  def new_admin_user
    password = set_password ? admin_password : "1!aA#{SecureRandom.alphanumeric(12)}"
    User.new(name: admin_name.to_s.strip, email: email, password: password, password_confirmation: password)
  end
end
