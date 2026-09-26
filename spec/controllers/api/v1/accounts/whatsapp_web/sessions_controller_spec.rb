require 'rails_helper'

RSpec.describe 'WhatsApp Web session API', type: :request do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: { 'link_method' => 'code' }, sync_templates: false)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/whatsapp_web_session" }
  let(:engine_url) { "http://engine:4000/sessions/#{channel.id}" }
  let(:env) do
    { WADESK_ENGINE_URL: 'http://engine:4000', WADESK_ENGINE_API_TOKEN: 'engine-token', WADESK_ENGINE_CALLBACK_BASE_URL: 'http://rails:3000' }
  end

  def json(body) = { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }

  it 'shows the live state with the current pairing code' do
    stub_request(:get, engine_url).to_return(json(state: 'qr_pending', pairing_code: 'ABCD1234'))

    with_modified_env(env) { get url, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('state' => 'qr_pending', 'pairing_code' => 'ABCD1234', 'link_method' => 'code')
  end

  it 'reports a number that is not linked' do
    stub_request(:get, engine_url).to_return(json(error: { code: 'session_not_found', message: 'x' }).merge(status: 404))

    with_modified_env(env) { get url, headers: admin.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'not_linked')
  end

  it 'reconnects, switching the link method when asked' do
    stub = stub_request(:put, engine_url).with(body: hash_including('link_method' => 'qr')).to_return(json(state: 'connecting'))

    with_modified_env(env) { post "#{url}/reconnect", params: { link_method: 'qr' }, headers: admin.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'connecting', 'link_method' => 'qr')
    expect(channel.reload.provider_config['link_method']).to eq('qr')
    expect(stub).to have_been_requested
  end

  it 'logs the number out and records it on the inbox' do
    stub_request(:delete, engine_url).to_return(status: 204)

    with_modified_env(env) { delete url, headers: admin.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'logged_out')
    expect(channel.reload.provider_config).to include('connection_state' => 'logged_out', 'connection_reason' => 'logged_out_by_admin')
    expect(channel.reauthorization_required?).to be false # deliberate, so no alert
  end

  it 'answers 502 when the engine is unavailable' do
    stub_request(:get, engine_url).to_return(status: 500, body: 'boom')

    with_modified_env(env) { get url, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:bad_gateway)
  end

  it 'is only for administrators' do
    with_modified_env(env) { get url, headers: agent.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is only for WhatsApp Web inboxes' do
    other = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)

    with_modified_env(env) do
      get "/api/v1/accounts/#{account.id}/inboxes/#{other.inbox.id}/whatsapp_web_session", headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:not_found)
  end
end
