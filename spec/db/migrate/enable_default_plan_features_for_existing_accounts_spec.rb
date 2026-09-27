require 'rails_helper'
require Rails.root.join('db/migrate/20260927100000_enable_default_plan_features_for_existing_accounts')

RSpec.describe EnableDefaultPlanFeaturesForExistingAccounts do
  let(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  it 'turns back on default-on plan features an older account is missing' do
    account = create(:account)
    account.disable_features!('campaigns', 'crm', 'help_center', 'labels', 'channel_tiktok')

    migrate

    expect(account.reload.enabled_features.keys).to include(*described_class::FEATURES)
  end

  it 'leaves default-off features as each account has them' do
    without_extras = create(:account)
    without_extras.disable_features!('whatsapp_campaign', 'delayed_automations', 'data_import')
    with_extras = create(:account)
    with_extras.enable_features!('whatsapp_campaign', 'data_import')

    migrate

    expect(without_extras.reload.enabled_features.keys).not_to include('whatsapp_campaign', 'delayed_automations', 'data_import')
    expect(with_extras.reload.enabled_features.keys).to include('whatsapp_campaign', 'data_import')
    expect(with_extras.enabled_features.keys).not_to include('delayed_automations')
  end
end
