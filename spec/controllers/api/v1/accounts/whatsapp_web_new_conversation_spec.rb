require 'rails_helper'

# WW-FR-25: agents can start a WhatsApp Web chat with a contact by phone number, without templates.
RSpec.describe 'Starting WhatsApp Web conversations', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:contact) { create(:contact, account: account, phone_number: '+919876543210') }
  let(:env) { { WADESK_ENGINE_URL: 'http://engine:4000', WADESK_ENGINE_API_TOKEN: 'engine-token' } }

  it 'creates the conversation and sends the first message as free text through the engine' do
    send_request = stub_request(:post, "http://engine:4000/sessions/#{channel.id}/messages")
                   .to_return(status: 201, body: { id: '3EB0FIRST' }.to_json, headers: { 'Content-Type' => 'application/json' })

    with_modified_env(env) do
      perform_enqueued_jobs(only: SendReplyJob) do
        post "/api/v1/accounts/#{account.id}/conversations",
             params: { inbox_id: channel.inbox.id, contact_id: contact.id, message: { content: 'Hello! Your order is ready.' } },
             headers: agent.create_new_auth_token, as: :json
      end
    end

    expect(response).to have_http_status(:ok)
    conversation = channel.inbox.conversations.last
    expect(conversation.contact_inbox.source_id).to eq('919876543210')
    expect(conversation.messages.outgoing.last).to have_attributes(content: 'Hello! Your order is ready.', source_id: '3EB0FIRST')
    expect(send_request).to have_been_requested
  end
end
