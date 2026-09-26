require 'rails_helper'

RSpec.describe Wadesk::OptOutListener do
  include ActiveJob::TestHelper

  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }

  it 'is registered with the event dispatcher' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end

  it 'records an opt-out when a customer message "STOP" is created' do
    perform_enqueued_jobs(only: EventDispatcherJob) do
      create(:message, account: account, inbox: channel.inbox, conversation: conversation, sender: conversation.contact,
                       message_type: :incoming, content: 'STOP')
    end

    expect(Wadesk::ConsentEvent.marketing_state(conversation.contact)).to eq(:opted_out)
  end
end
