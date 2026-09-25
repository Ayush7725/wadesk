require 'rails_helper'

RSpec.describe 'Webhooks::WhatsappWebController', type: :request do
  let(:secret) { 'engine-webhook-secret-0123456789abcdef' }
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:body) { { event: 'connection', state: 'connected', me: { phone: '919812345678' } }.to_json }
  let(:timestamp) { Time.zone.now.to_i.to_s }

  def sign(body, timestamp, key = secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{timestamp}.#{body}")}"
  end

  def deliver(channel_id, body, timestamp: self.timestamp, signature: sign(body, timestamp))
    with_modified_env(WADESK_ENGINE_WEBHOOK_SECRET: secret) do
      post "/webhooks/whatsapp_web/#{channel_id}",
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-WaDesk-Timestamp' => timestamp, 'X-WaDesk-Signature' => signature }
    end
  end

  it 'stores the connection state from a signed event' do
    deliver(channel.id, body)

    expect(response).to have_http_status(:ok)
    expect(channel.reload.provider_config).to include(
      'connection_state' => 'connected', 'connected_phone' => '919812345678', 'connection_reason' => nil
    )
  end

  it 'stores the reason for a logout' do
    deliver(channel.id, { event: 'connection', state: 'logged_out', reason: 'unlinked_from_phone' }.to_json)

    expect(channel.reload.provider_config).to include('connection_state' => 'logged_out', 'connection_reason' => 'unlinked_from_phone')
  end

  it 'rejects a wrong signature' do
    deliver(channel.id, body, signature: sign(body, timestamp, 'another-secret'))

    expect(response).to have_http_status(:unauthorized)
    expect(channel.reload.provider_config).not_to have_key('connection_state')
  end

  it 'rejects a body that does not match its signature' do
    deliver(channel.id, body.sub('connected', 'failed'), signature: sign(body, timestamp))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects replays outside the 5 minute window' do
    old = 6.minutes.ago.to_i.to_s

    deliver(channel.id, body, timestamp: old, signature: sign(body, old))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects unsigned requests' do
    deliver(channel.id, body, timestamp: '', signature: '')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'acknowledges events for deleted or non-WhatsApp-Web channels so the engine stops retrying' do
    other = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)

    deliver(0, body)
    expect(response).to have_http_status(:ok)
    deliver(other.id, body)
    expect(response).to have_http_status(:ok)
    expect(other.reload.provider_config).not_to have_key('connection_state')
  end

  it 'rejects events it does not handle yet' do
    deliver(channel.id, { event: 'unknown' }.to_json)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
