require 'rails_helper'

# WaDesk: Official WhatsApp is a plan (whatsapp_official). New Official inboxes need it; existing ones keep working.
RSpec.describe WhatsappOfficialPlan do
  let(:account) { create(:account) }

  describe 'Channel::Whatsapp' do
    # Meta / 360dialog accept the credentials, so only the plan decides.
    before do
      stub_request(:any, /graph.facebook.com|360dialog/)
        .to_return(status: 200, body: { data: [{ id: 'random_id' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    %w[whatsapp_cloud default].each do |provider|
      context "with the #{provider} provider" do
        let(:channel) do
          build(:channel_whatsapp, account: account, provider: provider)
        end

        it 'is allowed when the account has WhatsApp Official' do
          expect(channel).to be_valid
        end

        it 'is rejected when the account does not have WhatsApp Official' do
          account.disable_features!('whatsapp_official')

          expect(channel).not_to be_valid
          expect(channel.errors[:base]).to include('WhatsApp Official is not enabled for this account')
        end
      end
    end

    it 'rejects switching an existing WhatsApp Web inbox to an Official provider without the plan' do
      account.enable_features!('whatsapp_web')
      channel = create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false)
      account.disable_features!('whatsapp_official')

      channel.reload.provider = 'whatsapp_cloud'

      expect(channel).not_to be_valid
      expect(channel.errors[:base]).to include('WhatsApp Official is not enabled for this account')
    end

    it 'does not gate WhatsApp Web inboxes on the Official plan' do
      account.disable_features!('whatsapp_official')
      account.enable_features!('whatsapp_web')

      expect(build(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {})).to be_valid
    end

    it 'keeps saving an existing Official inbox after the plan is turned off, and allows new ones once it is back on' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false)
      account.disable_features!('whatsapp_official')

      # A token refresh on the existing inbox, as Reauthorize / credential updates do.
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'rotated_key'))
      expect(channel.reload.provider_config['api_key']).to eq('rotated_key')

      account.enable_features!('whatsapp_official')
      expect(build(:channel_whatsapp, account: account, provider: 'whatsapp_cloud')).to be_valid
    end
  end

  describe 'Channel::TwilioSms' do
    it 'rejects Twilio WhatsApp when the account does not have WhatsApp Official' do
      account.disable_features!('whatsapp_official')
      channel = build(:channel_twilio_sms, :whatsapp, account: account)

      expect(channel).not_to be_valid
      expect(channel.errors[:base]).to include('WhatsApp Official is not enabled for this account')
    end

    it 'allows Twilio WhatsApp when the account has WhatsApp Official' do
      expect(build(:channel_twilio_sms, :whatsapp, account: account)).to be_valid
    end

    it 'does not gate Twilio SMS' do
      account.disable_features!('whatsapp_official')

      expect(build(:channel_twilio_sms, account: account)).to be_valid
    end

    it 'rejects switching an existing Twilio SMS inbox to WhatsApp without the plan' do
      channel = create(:channel_twilio_sms, account: account)
      account.disable_features!('whatsapp_official')

      channel.reload.medium = :whatsapp

      expect(channel).not_to be_valid
      expect(channel.errors[:base]).to include('WhatsApp Official is not enabled for this account')
    end

    it 'keeps saving an existing Twilio WhatsApp inbox after the plan is turned off' do
      channel = create(:channel_twilio_sms, :whatsapp, account: account)
      account.disable_features!('whatsapp_official')

      channel.update!(auth_token: 'rotated_token')
      expect(channel.reload.auth_token).to eq('rotated_token')
    end
  end
end
