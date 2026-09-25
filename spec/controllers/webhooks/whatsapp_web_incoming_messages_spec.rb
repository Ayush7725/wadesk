require 'rails_helper'

# End to end through the real webhook, job and incoming pipeline, using the engine's contract fixtures
# (wadesk-engine/contract/messages), so both sides are held to the same payloads.
RSpec.describe 'WhatsApp Web incoming messages', type: :request do
  include ActiveJob::TestHelper

  let(:secret) { 'engine-webhook-secret-0123456789abcdef' }
  let(:env) { { WADESK_ENGINE_WEBHOOK_SECRET: secret, WADESK_ENGINE_URL: 'http://engine:4000', WADESK_ENGINE_API_TOKEN: 'engine-token' } }
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  # Created up front, so its StartSessionJob is not run by perform_enqueued_jobs below.
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:media_url) { "http://engine:4000/sessions/#{channel.id}/media/3EB0A1B2C3D4E5F6" }
  let(:message) { inbox.messages.last }

  def contract(name)
    File.read(Rails.root.join("wadesk-engine/contract/messages/#{name}.json"))
  end

  def deliver(body)
    timestamp = Time.zone.now.to_i.to_s
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    with_modified_env(env) do
      perform_enqueued_jobs do
        post "/webhooks/whatsapp_web/#{channel.id}", params: body,
                                                     headers: { 'CONTENT_TYPE' => 'application/json', 'X-WaDesk-Timestamp' => timestamp,
                                                                'X-WaDesk-Signature' => signature }
      end
    end
    expect(response).to have_http_status(:ok)
  end

  def stub_media(content_type, filename, body = 'media-bytes')
    stub_request(:get, media_url)
      .with(headers: { 'Authorization' => 'Bearer engine-token' })
      .to_return(status: 200, body: body,
                 headers: { 'Content-Type' => content_type, 'Content-Disposition' => "attachment; filename*=UTF-8''#{filename}" })
  end

  # The dedup lock lives in Redis and is not rolled back between examples; the fixtures share message ids.
  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'creates the contact, conversation and message for a text' do
    deliver(contract('text'))

    expect(message).to have_attributes(content: 'Hi, what is the price of the teak sofa?', message_type: 'incoming', source_id: '3EB0A1B2C3D4E5F6')
    expect(message.sender).to have_attributes(name: 'Ravi Kumar', phone_number: '+919876543210')
    expect(message.conversation.contact_inbox.source_id).to eq('919876543210')
  end

  it 'links replies to the quoted message' do
    deliver(contract('text'))
    quoted = inbox.messages.last
    quoted.update!(source_id: '3EB0FFEEDDCCBBAA')

    deliver(contract('text_reply').sub('3EB0A1B2C3D4E5F6', '3EB0A1B2C3D4E5F7'))

    expect(message.content_attributes).to include('in_reply_to' => quoted.id, 'in_reply_to_external_id' => '3EB0FFEEDDCCBBAA')
    expect(message.conversation).to eq(quoted.conversation)
  end

  it 'downloads images from the engine with the caption as content' do
    stub_media('image/jpeg', '3EB0A1B2C3D4E5F6.jpeg')

    deliver(contract('image'))

    expect(message.content).to eq('Like this one')
    expect(message.attachments.first).to have_attributes(file_type: 'image')
    expect(message.attachments.first.file.filename.to_s).to eq('3EB0A1B2C3D4E5F6.jpeg')
  end

  it 'stores voice notes as audio' do
    stub_media('audio/ogg; codecs=opus', '3EB0A1B2C3D4E5F6.ogg')

    deliver(contract('voice_note'))

    expect(message.attachments.first).to have_attributes(file_type: 'audio')
  end

  it 'keeps document file names' do
    stub_media('application/pdf', 'floor-plan.pdf', '%PDF-1.4')

    deliver(contract('document'))

    expect(message.content).to eq('Our room')
    expect(message.attachments.first).to have_attributes(file_type: 'file')
    expect(message.attachments.first.file.filename.to_s).to eq('floor-plan.pdf')
  end

  it 'stores locations' do
    deliver(contract('location'))

    expect(message.attachments.first).to have_attributes(file_type: 'location', coordinates_lat: 26.9124, coordinates_long: 75.7873,
                                                         fallback_title: 'Home, Jaipur, Rajasthan')
  end

  it 'stores shared contact cards' do
    deliver(contract('contact_card'))

    expect(message.content).to eq('Anita Sharma')
    expect(message.attachments.first).to have_attributes(file_type: 'contact')
  end

  it 'marks message kinds the inbox cannot show' do
    deliver(contract('unsupported'))

    expect(message.content_attributes).to include('is_unsupported' => true)
  end

  it 'identifies customers WhatsApp only shows by privacy ID (LID)' do
    deliver(contract('lid_only'))

    expect(message.sender).to have_attributes(name: 'Ravi Kumar', phone_number: nil)
    expect(message.conversation.contact_inbox.source_id).to eq('123456789012345@lid')
  end

  it 'prefers the phone number when WhatsApp provides both' do
    deliver(contract('lid_with_phone'))

    expect(message.sender.phone_number).to eq('+919876543210')
    expect(message.conversation.contact_inbox.source_id).to eq('919876543210')
  end

  it 'creates each WhatsApp message once even if delivered twice' do
    deliver(contract('text'))
    deliver(contract('text'))

    expect(inbox.messages.where(source_id: '3EB0A1B2C3D4E5F6').count).to eq(1)
  end

  it 'continues the open conversation for the next message' do
    deliver(contract('text'))
    deliver(contract('text').sub('3EB0A1B2C3D4E5F6', '3EB0A1B2C3D4E5F7'))

    expect(inbox.conversations.count).to eq(1)
    expect(inbox.messages.count).to eq(2)
  end
end
