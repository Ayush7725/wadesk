# WaDesk: append-only history of marketing consent per contact (ADR-0006, SAFE-FR-10..14).
class CreateWadeskConsentEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :wadesk_consent_events do |t|
      t.references :account, null: false, index: false
      t.references :contact, null: false, index: false
      t.references :user, null: true, index: false # who recorded it; empty when recorded by the system
      t.integer :kind, null: false # opt_in / opt_out
      t.string :purpose, null: false, default: 'marketing'
      t.string :source, null: false # e.g. whatsapp_message, form, import, agent, api
      t.string :evidence, limit: 255 # e.g. the message text that triggered an opt-out
      t.datetime :created_at, null: false
    end
    add_index :wadesk_consent_events, [:account_id, :contact_id, :created_at], name: 'index_wadesk_consent_events_on_contact_history'
  end
end
