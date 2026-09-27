# WaDesk: the dashboard now hides a feature that is off for the account (sidebar and direct URL).
# `enabled: true` in features.yml only reaches accounts created after a flag existed, so older
# accounts may have some of these off without anyone choosing that. Turn the default-on features
# the operator can switch per client back on for every existing account, so nobody loses a menu.
# Default-off features (whatsapp_campaign, delayed_automations, data_import) are left as they are.
class EnableDefaultPlanFeaturesForExistingAccounts < ActiveRecord::Migration[7.1]
  FEATURES = %w[
    campaigns canned_responses macros voice_recorder help_center automations agent_bots
    auto_resolve_conversations reports crm companies custom_attributes labels
    agent_management team_management inbox_management integrations
    channel_website channel_email channel_facebook channel_instagram channel_tiktok
  ].freeze

  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!(*FEATURES) }
    end
  end
end
