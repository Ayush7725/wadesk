require 'rails_helper'

RSpec.describe Wadesk::Safety::NewChatLimit do
  let(:account) do
    create(:account, custom_attributes: { 'wadesk_whatsapp_web_daily_new_chats' => 2 }).tap { |a| a.enable_features!('whatsapp_web') }
  end
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:inbox) { channel.inbox }

  def conversation_with(phone)
    contact = create(:contact, account: account, phone_number: "+#{phone}")
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: phone)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def outgoing(conversation, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, **attrs)
  end

  def limit_for(message) = described_class.new(message: message)

  it 'allows new chats up to the limit, then blocks the next one' do
    # Each message is checked when it is sent, before the next one exists.
    outgoing(conversation_with('919800000001'))
    expect(limit_for(outgoing(conversation_with('919800000002'))).exceeded?).to be false
    expect(limit_for(outgoing(conversation_with('919800000003'))).exceeded?).to be true
  end

  it 'never limits replies to customers who wrote in' do
    2.times { |i| outgoing(conversation_with("91980000001#{i}")) }
    customer = conversation_with('919800000099')
    create(:message, account: account, inbox: inbox, conversation: customer, message_type: :incoming)

    expect(limit_for(outgoing(customer)).exceeded?).to be false
  end

  it 'counts each started chat once, however many messages follow' do
    first = conversation_with('919800000001')
    outgoing(first)
    outgoing(conversation_with('919800000002'))

    expect(limit_for(outgoing(first)).exceeded?).to be false
  end

  it 'ignores failed messages and chats started more than 24 hours ago' do
    outgoing(conversation_with('919800000001'), status: :failed)
    outgoing(conversation_with('919800000002'), created_at: 25.hours.ago)

    expect(limit_for(outgoing(conversation_with('919800000003'))).exceeded?).to be false
  end

  it 'defaults to 20 when the operator has not set a limit' do
    account.update!(custom_attributes: {})

    expect(limit_for(outgoing(conversation_with('919800000001'))).daily_limit).to eq(20)
  end

  describe 'when sending' do
    let(:env) { { WADESK_ENGINE_URL: 'http://engine:4000', WADESK_ENGINE_API_TOKEN: 'engine-token' } }

    it 'fails the message with an explanation instead of sending it' do
      2.times { |i| outgoing(conversation_with("91980000002#{i}")) }
      blocked = outgoing(conversation_with('919800000030'), content: 'Special offer!')

      with_modified_env(env) { channel.provider_service.send_message('919800000030', blocked) }

      expect(blocked.reload).to have_attributes(status: 'failed', external_error: /already started 2 new chats in the last 24 hours/)
      expect(WebMock).not_to have_requested(:post, %r{engine:4000/sessions/\d+/messages})
    end
  end
end
