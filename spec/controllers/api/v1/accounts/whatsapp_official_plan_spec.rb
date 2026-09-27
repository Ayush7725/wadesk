require 'rails_helper'

# WaDesk: creating Official WhatsApp inboxes through the API needs the whatsapp_official plan.
RSpec.describe 'Official WhatsApp plan', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'POST /api/v1/accounts/{account.id}/inboxes with a WhatsApp Cloud channel' do
    let(:params) do
      {
        name: 'Sales',
        channel: {
          type: 'whatsapp', phone_number: '+919876543210', provider: 'whatsapp_cloud',
          provider_config: { api_key: 'token', phone_number_id: '123', business_account_id: '456' }
        }
      }
    end

    # Meta accepts the credentials and the webhook registration, so only the plan decides.
    before do
      stub_request(:any, /graph.facebook.com/)
        .to_return(status: 200, body: { data: [{ id: '123' }], success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 422 when the account does not have WhatsApp Official' do
      account.disable_features!('whatsapp_official')

      expect do
        post "/api/v1/accounts/#{account.id}/inboxes", params: params, headers: admin.create_new_auth_token, as: :json
      end.not_to change(Inbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('WhatsApp Official is not enabled for this account')
    end

    it 'creates the inbox when the account has WhatsApp Official' do
      post "/api/v1/accounts/#{account.id}/inboxes", params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.inboxes.last.channel).to have_attributes(provider: 'whatsapp_cloud', phone_number: '+919876543210')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/channels/twilio_channel for WhatsApp' do
    let(:params) do
      { twilio_channel: { account_sid: 'sid', auth_token: 'token', phone_number: '+919876543210', name: 'Twilio WhatsApp', medium: 'whatsapp' } }
    end

    before do
      messages = instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList, list: [])
      twilio_client = instance_double(Twilio::REST::Client, messages: messages)
      allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
      allow(Twilio::WebhookSetupService).to receive(:new).and_return(instance_double(Twilio::WebhookSetupService, perform: nil))
    end

    it 'returns 422 when the account does not have WhatsApp Official' do
      account.disable_features!('whatsapp_official')

      expect do
        post api_v1_account_channels_twilio_channel_path(account), params: params, headers: admin.create_new_auth_token, as: :json
      end.not_to change(Inbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('WhatsApp Official is not enabled for this account')
    end

    it 'creates the inbox when the account has WhatsApp Official' do
      post api_v1_account_channels_twilio_channel_path(account), params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.inboxes.last.channel).to have_attributes(medium: 'whatsapp', phone_number: 'whatsapp:+919876543210')
    end
  end
end
