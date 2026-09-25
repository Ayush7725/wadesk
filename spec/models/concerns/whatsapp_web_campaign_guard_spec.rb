require 'rails_helper'

RSpec.describe WhatsappWebCampaignGuard do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web', 'whatsapp_campaign') } }

  it 'rejects campaigns on WhatsApp Web inboxes (SAFE-FR-01)' do
    channel = create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false)
    campaign = build(:campaign, account: account, inbox: channel.inbox)

    expect(campaign).not_to be_valid
    expect(campaign.errors[:inbox]).to include(/not available for WhatsApp Web inboxes/)
  end

  it 'still allows campaigns on other WhatsApp inboxes' do
    official = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)

    expect(build(:campaign, account: account, inbox: official.inbox).errors[:inbox]).to be_empty
  end
end
