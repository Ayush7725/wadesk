require 'rails_helper'

RSpec.describe WhatsappWebChannel do
  let(:account) { create(:account) }
  let(:channel) { build(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }

  before { account.enable_features!('whatsapp_web') }

  describe 'plan gating' do
    it 'allows WhatsApp Web inboxes when the account has the feature' do
      expect(channel).to be_valid
    end

    it 'rejects WhatsApp Web inboxes when the account does not have the feature' do
      account.disable_features!('whatsapp_web')

      expect(channel).not_to be_valid
      expect(channel.errors[:provider]).to include('WhatsApp Web is not enabled for this account')
    end

    it 'keeps existing inboxes valid after the feature is disabled' do
      channel.save!
      account.disable_features!('whatsapp_web')

      expect(channel.reload).to be_valid
    end
  end

  describe 'link method' do
    it 'defaults to QR code' do
      channel.valid?

      expect(channel.provider_config['link_method']).to eq('qr')
    end

    it 'accepts pairing codes' do
      channel.provider_config = { 'link_method' => 'code' }

      expect(channel).to be_valid
    end

    it 'rejects unknown link methods' do
      channel.provider_config = { 'link_method' => 'sms' }

      expect(channel).not_to be_valid
    end
  end

  describe 'engine session lifecycle' do
    it 'starts the engine session after the inbox is created' do
      expect { channel.save! }.to have_enqueued_job(WhatsappWeb::StartSessionJob).with(channel)
    end

    it 'removes the engine session when the channel is destroyed' do
      channel.save!
      client = instance_double(WhatsappWeb::EngineClient, delete_session: nil)
      allow(WhatsappWeb::EngineClient).to receive(:new).and_return(client)

      channel.destroy!

      expect(client).to have_received(:delete_session).with(channel.id)
    end

    it 'does not touch the engine for other WhatsApp providers' do
      allow(WhatsappWeb::EngineClient).to receive(:new)

      expect do
        create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false).destroy!
      end.not_to have_enqueued_job(WhatsappWeb::StartSessionJob)
      expect(WhatsappWeb::EngineClient).not_to have_received(:new)
    end
  end

  it 'uses the Baileys provider service' do
    expect(channel.provider_service).to be_a(Whatsapp::Providers::WhatsappBaileysService)
  end
end
