require 'rails_helper'

describe Whatsapp::Providers::WhatsappBaileysService do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, message_templates_last_updated: nil) }
  let(:service) { described_class.new(whatsapp_channel: channel) }

  describe '#sync_templates' do
    it 'marks templates as synced without calling any API, so the scheduler moves on' do
      freeze_time do
        service.sync_templates

        expect(channel.reload.message_templates_last_updated).to eq(Time.zone.now)
      end
    end
  end
end
