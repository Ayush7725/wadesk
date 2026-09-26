# WaDesk: one entry in a contact's marketing consent history. Entries are never changed or deleted;
# the current state is the latest entry (ADR-0006 decision 4, SAFE-NFR-02).
# == Schema Information
#
# Table name: wadesk_consent_events
#
#  id         :bigint           not null, primary key
#  evidence   :string(255)
#  kind       :integer          not null
#  purpose    :string           default("marketing"), not null
#  source     :string           not null
#  created_at :datetime         not null
#  account_id :bigint           not null
#  contact_id :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  index_wadesk_consent_events_on_contact_history  (account_id,contact_id,created_at)
#
class Wadesk::ConsentEvent < ApplicationRecord
  self.table_name = 'wadesk_consent_events'

  belongs_to :account
  belongs_to :contact
  belongs_to :user, optional: true

  enum :kind, { opt_in: 0, opt_out: 1 }

  validates :purpose, :source, presence: true

  scope :for_contact, ->(contact, purpose: 'marketing') { where(contact: contact, purpose: purpose).order(:created_at, :id) }

  def readonly?
    persisted?
  end

  # :opted_in, :opted_out or :unknown (no history). Enquiring is not consent (04-safety-requirements §2).
  def self.marketing_state(contact)
    latest = for_contact(contact).last
    return :unknown if latest.nil?

    latest.opt_in? ? :opted_in : :opted_out
  end
end
