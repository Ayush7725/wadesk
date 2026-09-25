require 'rails_helper'

describe Whatsapp::Providers::WhatsappBaileysService do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, message_templates_last_updated: nil) }
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:env) { { WADESK_ENGINE_URL: 'http://engine:4000', WADESK_ENGINE_API_TOKEN: 'engine-token' } }
  let(:send_url) { "http://engine:4000/sessions/#{channel.id}/messages" }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '919876543210') }
  let(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
  end
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, content: 'Price is 45,000')
  end

  # A multipart field's value. Bodies with files contain binary bytes, so work on bytes, not text patterns.
  def field(body, name)
    bytes = body.b
    marker = "name=\"#{name}\"\r\n\r\n".b
    start = bytes.index(marker)
    return if start.nil?

    value_start = start + marker.bytesize
    bytes[value_start...bytes.index("\r\n--".b, value_start)].force_encoding(Encoding::UTF_8)
  end

  def engine_created(id = 'X')
    { status: 201, body: { id: id }.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  describe '#sync_templates' do
    it 'marks templates as synced without calling any API, so the scheduler moves on' do
      freeze_time do
        service.sync_templates

        expect(channel.reload.message_templates_last_updated).to eq(Time.zone.now)
      end
    end
  end

  describe '#send_message' do
    it 'sends the text and returns the WhatsApp message id' do
      request = stub_request(:post, send_url).with(headers: { 'Authorization' => 'Bearer engine-token' }).to_return(engine_created('3EB0SENT'))

      id = with_modified_env(env) { service.send_message('919876543210', message) }

      expect(id).to eq('3EB0SENT')
      expect(request.with { |req| field(req.body, 'to') == '919876543210' && field(req.body, 'text') == 'Price is 45,000' }).to have_been_made
    end

    it 'uploads the first attachment with its name and type, the text as caption' do
      pdf = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
      message.attachments.create!(account: account, file_type: :file, file: pdf)
      stub_request(:post, send_url).to_return(engine_created)

      with_modified_env(env) { service.send_message('919876543210', message.reload) }

      expect(WebMock).to(have_requested(:post, send_url).with do |req|
        req.body.b.include?('name="file"; filename="sample.pdf"') && req.body.b.include?('Content-Type: application/pdf') &&
          field(req.body, 'text') == 'Price is 45,000'
      end)
    end

    it 'sends recordings stored as audio/opus as Ogg voice notes' do
      recording = fixture_file_upload(Rails.root.join('spec/assets/sample.ogg'), 'audio/opus')
      message.attachments.create!(account: account, file_type: :audio, file: recording)
      stub_request(:post, send_url).to_return(engine_created)

      with_modified_env(env) { service.send_message('919876543210', message.reload) }

      expect(WebMock).to(have_requested(:post, send_url).with { |req| req.body.b.include?('Content-Type: audio/ogg') })
    end

    it 'quotes the replied-to message with its text and direction' do
      quoted = create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming,
                                content: 'Is it available in brown?', source_id: 'IN1')
      message.update!(content_attributes: { in_reply_to: quoted.id, in_reply_to_external_id: 'IN1' })
      stub_request(:post, send_url).to_return(engine_created)

      with_modified_env(env) { service.send_message('919876543210', message) }

      expect(WebMock).to(have_requested(:post, send_url).with do |req|
        field(req.body, 'reply_to_id') == 'IN1' && field(req.body, 'reply_to_text') == 'Is it available in brown?' &&
          field(req.body, 'reply_to_from_me') == 'false'
      end)
    end

    it 'fails the message with a reason agents can act on' do
      stub_request(:post, send_url).to_return(status: 409, body: { error: { code: 'not_connected', message: 'x' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      id = with_modified_env(env) { service.send_message('919876543210', message) }

      expect(id).to be_nil
      expect(message.reload).to have_attributes(status: 'failed', external_error: /WhatsApp Web is not connected/)
    end

    it 'raises on rate limits and engine errors so the send job retries later' do
      stub_request(:post, send_url).to_return(status: 429, body: { error: { code: 'rate_limited', message: 'x' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      expect { with_modified_env(env) { service.send_message('919876543210', message) } }.to raise_error(WhatsappWeb::EngineClient::Error)
      expect(message.reload.status).not_to eq('failed')
    end
  end

  it 'delivers an agent reply end to end through the send job' do
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, content: 'Hi')
    stub_request(:post, send_url).to_return(engine_created('3EB0REPLY'))
    reply = create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, content: 'Hello!')

    with_modified_env(env) { SendReplyJob.perform_now(reply.id) }

    expect(reply.reload.source_id).to eq('3EB0REPLY')
  end
end
