# WaDesk: lets inbox administrators link, re-link and log out a WhatsApp Web number (WW-FR-02/03/05/06).
class Api::V1::Accounts::WhatsappWeb::SessionsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel

  # Live state from the engine, including the current QR code or pairing code while waiting to be linked.
  def show
    render json: session_payload(engine.session(@channel.id))
  rescue ::WhatsappWeb::EngineClient::Error => e
    return render json: session_payload('state' => 'not_linked') if e.code == 'session_not_found'

    render_engine_error(e)
  end

  # Starts linking again, optionally switching between QR code and pairing code.
  def reconnect
    @channel.update!(provider_config: @channel.provider_config.merge('link_method' => params[:link_method])) if params[:link_method].present?
    render json: session_payload(engine.upsert_session(@channel))
  rescue ::WhatsappWeb::EngineClient::Error => e
    render_engine_error(e)
  end

  # Logs the device out of WhatsApp and forgets its credentials; the inbox and its history stay.
  def destroy
    engine.delete_session(@channel.id)
    ::WhatsappWeb::ConnectionUpdateService.new(channel: @channel, payload: { 'state' => 'logged_out', 'reason' => 'logged_out_by_admin' }).perform
    render json: session_payload('state' => 'logged_out')
  rescue ::WhatsappWeb::EngineClient::Error => e
    render_engine_error(e)
  end

  private

  def fetch_channel
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :update?
    @channel = inbox.channel
    raise ActiveRecord::RecordNotFound unless @channel.is_a?(Channel::Whatsapp) && @channel.whatsapp_web?
  end

  def engine = ::WhatsappWeb::EngineClient.new

  def session_payload(session)
    session.slice('state', 'qr', 'pairing_code', 'me', 'last_error').merge('link_method' => @channel.provider_config['link_method'])
  end

  def render_engine_error(error)
    render json: { error: error.message }, status: :bad_gateway
  end
end
