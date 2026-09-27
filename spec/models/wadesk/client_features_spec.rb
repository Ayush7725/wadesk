require 'rails_helper'

# WaDesk: the allow-list of features the operator may show or hide per client.
RSpec.describe Wadesk::ClientFeatures do
  it 'only lists existing account feature flags that are not the WhatsApp plan switches' do
    flags = Featurable::FEATURE_LIST.pluck('name')

    expect(described_class::NAMES - flags).to be_empty
    expect(described_class::NAMES).not_to include('whatsapp_official', 'whatsapp_web', 'captain_integration', 'api_and_webhooks')
    expect(described_class::NAMES.size).to eq(25)
  end

  it 'offers exactly the features the client dashboard hides when they are switched off' do
    constants = Rails.root.join('app/javascript/dashboard/featureFlags.js').read.scan(/(\w+): '([a-z0-9_]+)'/).to_h
    gate = Rails.root.join('app/javascript/dashboard/helper/featureGate.js').read
    dashboard_list = gate[/OPERATOR_FEATURE_FLAGS = \[(.*?)\]/m, 1].scan(/FEATURE_FLAGS\.(\w+)/).flatten.map { |name| constants.fetch(name) }

    expect(dashboard_list).to match_array(described_class::NAMES)
  end

  it 'warns in plain words when a feature with lasting effects is turned off' do
    warnings = described_class::BY_NAME.transform_values(&:off_warning).compact

    expect(warnings.except(*warnings.keys.grep(/\Achannel_/))).to eq(
      'campaigns' => 'Website pop-up campaigns stop showing', 'whatsapp_campaign' => 'Scheduled WhatsApp campaigns will not be sent',
      'auto_resolve_conversations' => 'Auto-resolve already set up keeps running', 'delayed_automations' => 'Waiting delayed steps are dropped',
      'agent_bots' => 'Bots already attached to inboxes keep replying', 'integrations' => 'Connected integrations keep working'
    )
    expect(warnings.keys.grep(/\Achannel_/).map { |name| warnings[name] }.uniq).to eq(['Existing inboxes of this type keep working'])
    expect(warnings.keys.grep(/\Achannel_/).size).to eq(5)
  end
end
