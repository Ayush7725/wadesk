require 'rails_helper'

RSpec.describe WhatsappWeb::StartSessionJob do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }

  it 'asks the engine to start the session' do
    client = instance_double(WhatsappWeb::EngineClient, upsert_session: {})
    allow(WhatsappWeb::EngineClient).to receive(:new).and_return(client)

    described_class.perform_now(channel)

    expect(client).to have_received(:upsert_session).with(channel)
  end
end
