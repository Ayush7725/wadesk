require 'rails_helper'

describe WhatsappWeb::EngineClient do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: '+919812345678',
                              provider_config: { 'link_method' => 'code' }, sync_templates: false)
  end
  let(:env) do
    { 'WADESK_ENGINE_URL' => 'http://engine:4000', 'WADESK_ENGINE_API_TOKEN' => 'engine-token',
      'FRONTEND_URL' => 'https://app.example.com', 'WADESK_ENGINE_CALLBACK_BASE_URL' => nil }
  end
  let(:client) { described_class.new }

  it 'creates the session with the number, callback URL and link method' do
    stub = stub_request(:put, "http://engine:4000/sessions/#{channel.id}")
           .with(headers: { 'Authorization' => 'Bearer engine-token' },
                 body: { phone_number: '919812345678', webhook_url: "https://app.example.com/webhooks/whatsapp_web/#{channel.id}",
                         link_method: 'code' }.to_json)
           .to_return(status: 202, body: { state: 'connecting' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = with_modified_env(env) { client.upsert_session(channel) }

    expect(stub).to have_been_requested
    expect(result).to eq('state' => 'connecting')
  end

  it 'uses the internal callback base URL when configured' do
    stub = stub_request(:put, "http://engine:4000/sessions/#{channel.id}")
           .with(body: hash_including('webhook_url' => "http://rails:3000/webhooks/whatsapp_web/#{channel.id}"))
           .to_return(status: 202, body: '{}')

    with_modified_env(env.merge('WADESK_ENGINE_CALLBACK_BASE_URL' => 'http://rails:3000')) { client.upsert_session(channel) }

    expect(stub).to have_been_requested
  end

  it 'raises with the engine error code on failure' do
    stub_request(:get, 'http://engine:4000/sessions/42')
      .to_return(status: 401, body: { error: { code: 'unauthorized', message: 'Invalid API token' } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect { with_modified_env(env) { client.session(42) } }
      .to raise_error(described_class::Error, /401 unauthorized: Invalid API token/)
  end

  it 'sends no JSON content type on requests without a body' do
    stub = stub_request(:delete, 'http://engine:4000/sessions/42')
           .with { |request| request.headers['Content-Type'].nil? }
           .to_return(status: 204)

    with_modified_env(env) { client.delete_session(42) }

    expect(stub).to have_been_requested
  end

  it 'builds well-formed multipart uploads when a file is attached' do
    stub_request(:post, 'http://engine:4000/sessions/7/messages').to_return(
      status: 201, body: { id: 'X' }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    file = described_class::UploadPart.new(StringIO.new('%PDF'), 'quote.pdf', 'application/pdf')

    with_modified_env(env) { client.send_message(7, { to: '919876543210', text: 'Quotation', file: file }) }

    # Every part's headers must end with a blank line before its value (HTTParty's streaming mode got this wrong).
    expect(WebMock).to(have_requested(:post, 'http://engine:4000/sessions/7/messages').with do |req|
      body = req.body.b
      body.include?("name=\"to\"\r\n\r\n919876543210\r\n") && body.include?("name=\"text\"\r\n\r\nQuotation\r\n") &&
        body.include?("filename=\"quote.pdf\"\r\nContent-Type: application/pdf\r\n\r\n%PDF\r\n")
    end)
  end

  it 'treats deleting an unknown session as done' do
    stub_request(:delete, 'http://engine:4000/sessions/42')
      .to_return(status: 404, body: { error: { code: 'session_not_found', message: 'Session 42 not found' } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect { with_modified_env(env) { client.delete_session(42) } }.not_to raise_error
  end

  it 'raises other delete failures so the deletion is retried' do
    stub_request(:delete, 'http://engine:4000/sessions/42').to_return(status: 500, body: 'boom')

    expect { with_modified_env(env) { client.delete_session(42) } }.to raise_error(described_class::Error)
  end
end
