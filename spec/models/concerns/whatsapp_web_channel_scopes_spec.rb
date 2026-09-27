require 'rails_helper'

RSpec.describe WhatsappWebChannel do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }

  def number(config)
    create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false)
      .tap { |channel| channel.update_columns(provider_config: config) } # rubocop:disable Rails/SkipsModelValidations
  end

  it 'splits WhatsApp Web numbers into connected and needing attention, never-linked included' do
    connected = number('connection_state' => 'connected')
    logged_out = number('connection_state' => 'logged_out')
    never_linked = number({})
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    expect(Channel::Whatsapp.whatsapp_web).to contain_exactly(connected, logged_out, never_linked)
    expect(Channel::Whatsapp.whatsapp_web_connected).to contain_exactly(connected)
    expect(Channel::Whatsapp.whatsapp_web_needing_attention).to contain_exactly(logged_out, never_linked)
  end
end
