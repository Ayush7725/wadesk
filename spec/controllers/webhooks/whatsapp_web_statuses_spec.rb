require 'rails_helper'

# Delivery receipts end to end through the webhook, job and status pipeline, using the engine's contract fixtures.
RSpec.describe 'WhatsApp Web delivery statuses', type: :request do
  include ActiveJob::TestHelper

  let(:secret) { 'engine-webhook-secret-0123456789abcdef' }
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '919876543210') }
  let(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
  end
  let!(:message) do
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing,
                     source_id: '3EB0OUT1234567', status: :sent)
  end

  def deliver(name)
    body = File.read(Rails.root.join("wadesk-engine/contract/statuses/#{name}.json"))
    timestamp = Time.zone.now.to_i.to_s
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    with_modified_env(WADESK_ENGINE_WEBHOOK_SECRET: secret) do
      perform_enqueued_jobs do
        post "/webhooks/whatsapp_web/#{channel.id}", params: body,
                                                     headers: { 'CONTENT_TYPE' => 'application/json', 'X-WaDesk-Timestamp' => timestamp,
                                                                'X-WaDesk-Signature' => signature }
      end
    end
    expect(response).to have_http_status(:ok)
  end

  it 'moves the ticks forward as WhatsApp reports delivery and reading' do
    deliver('delivered')
    expect(message.reload.status).to eq('delivered')

    deliver('read')
    expect(message.reload.status).to eq('read')
  end

  it 'never moves a read message back to delivered' do
    deliver('read')
    deliver('delivered')

    expect(message.reload.status).to eq('read')
  end

  it 'shows messages WhatsApp could not deliver as failed' do
    deliver('failed')

    expect(message.reload.status).to eq('failed')
  end

  it 'handles receipts from privacy-ID (LID) recipients' do
    deliver('read_lid')

    expect(message.reload.status).to eq('read')
  end
end
