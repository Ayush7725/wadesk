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

    it 'rejects switching an existing Official inbox to WhatsApp Web without the feature' do
      official = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      account.disable_features!('whatsapp_web')

      official.reload.provider = 'baileys'

      expect(official).not_to be_valid
      expect(official.errors[:provider]).to include('WhatsApp Web is not enabled for this account')
    end

    it 'keeps existing inboxes valid after the feature is disabled' do
      channel.save!
      account.disable_features!('whatsapp_web')

      expect(channel.reload).to be_valid
    end

    it 'keeps saving connection updates on existing inboxes after the feature is disabled' do
      channel.save!
      account.disable_features!('whatsapp_web')

      WhatsappWeb::ConnectionUpdateService.new(channel: channel.reload, payload: { 'state' => 'connected', 'me' => { 'phone' => '919876543210' } })
                                          .perform

      expect(channel.reload.provider_config).to include('connection_state' => 'connected', 'connected_phone' => '919876543210')
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

  # M2.6: features that only exist for the Official Cloud API must skip or clearly reject WhatsApp Web
  # inboxes instead of calling Meta or failing later.
  describe 'Cloud-only features' do
    let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
    let!(:channel) do
      create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false,
                                message_templates_last_updated: nil, phone_number_health_checked_at: nil)
    end
    let(:inbox) { channel.inbox }

    it 'is never picked by the phone number health sync' do
      expect { Channels::Whatsapp::HealthSyncSchedulerJob.perform_now }.not_to have_enqueued_job(Channels::Whatsapp::HealthSyncJob)
    end

    it 'syncs templates without calling any API' do
      freeze_time do
        # A fresh instance: the factory stubs sync_templates on the created object.
        Channels::Whatsapp::TemplatesSyncJob.perform_now(Channel::Whatsapp.find(channel.id))

        expect(channel.reload.message_templates_last_updated).to eq(Time.zone.now)
      end
    end

    it 'does not offer WhatsApp calling' do
      expect(channel.voice_calling_supported?).to be(false)
      expect { channel.enable_voice_calling! }.to raise_error(/requires a whatsapp_cloud inbox/)
    end

    it 'rejects contact information requests' do
      expect { channel.send_contact_info_request('919876543210', nil) }.to raise_error(NotImplementedError)
    end

    it 'rejects the business management token' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)

      expect { Whatsapp::BusinessManagementTokenService.new(channel).update!('token') }
        .to raise_error(ArgumentError, /only supported for WhatsApp Embedded Signup inboxes/)
    end

    describe 'inbox health endpoint', type: :request do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'explains that health data needs the Cloud API' do
        get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/health", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to match(/only available for WhatsApp Cloud API/)
      end
    end

    describe 'CSAT surveys' do
      let(:contact) { create(:contact, account: account) }
      let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '919876543210') }
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

      it 'sends the survey as a normal message instead of a template' do
        inbox.update!(csat_survey_enabled: true)
        # The customer's message first: an incoming message re-opens a resolved conversation.
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
        conversation.resolved!
        survey = instance_double(MessageTemplates::Template::CsatSurvey, perform: nil)
        allow(MessageTemplates::Template::CsatSurvey).to receive(:new).and_return(survey)

        CsatSurveyService.new(conversation: conversation).perform

        expect(survey).to have_received(:perform)
      end
    end
  end
end
