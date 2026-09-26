require 'rails_helper'

RSpec.describe Wadesk::Safety::OptOutDetector do
  let(:account) { create(:account).tap { |a| a.enable_features!('whatsapp_web') } }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false) }
  let(:contact) { create(:contact, account: account, name: 'Ravi Kumar') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact) }

  def incoming(content, conv: conversation)
    create(:message, account: account, inbox: conv.inbox, conversation: conv, sender: conv.contact, message_type: :incoming, content: content)
  end

  def detect(message) = described_class.new(message: message).perform

  it 'records a marketing opt-out and tells agents in the conversation' do
    detect(incoming('STOP'))

    event = Wadesk::ConsentEvent.for_contact(contact).last
    expect(event).to have_attributes(kind: 'opt_out', purpose: 'marketing', source: 'whatsapp_message', evidence: 'STOP', user_id: nil)
    expect(conversation.messages.activity.last.content)
      .to eq('Ravi Kumar opted out of marketing messages ("STOP"). You can still reply to their questions.')
  end

  ['Stop!', '  stop 🙏 ', 'UNSUBSCRIBE', 'Opt-out', 'band karo', 'Mat bhejo.', 'मत भेजो', 'बंद कर दो'].each do |text|
    it "recognises #{text.inspect}" do
      detect(incoming(text))

      expect(Wadesk::ConsentEvent.marketing_state(contact)).to eq(:opted_out)
    end
  end

  ["please don't stop my order", 'stop by the shop tomorrow?', 'band'].each do |text|
    it "ignores #{text.inspect} (not a whole opt-out message)" do
      detect(incoming(text))

      expect(Wadesk::ConsentEvent.marketing_state(contact)).to eq(:unknown)
    end
  end

  it 'ignores agents\' messages and non-WhatsApp inboxes' do
    detect(create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, content: 'STOP'))
    web = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
    detect(incoming('STOP', conv: web))

    expect(Wadesk::ConsentEvent.marketing_state(contact)).to eq(:unknown)
  end

  it 'records a repeated STOP only once' do
    2.times { detect(incoming('STOP')) }

    expect(Wadesk::ConsentEvent.for_contact(contact).count).to eq(1)
    expect(conversation.messages.activity.count).to eq(1)
  end

  it 'uses the operator\'s keyword list when configured' do
    with_modified_env(WADESK_OPT_OUT_KEYWORDS: "remove me,\nno thanks") do
      detect(incoming('Remove me'))
      expect(Wadesk::ConsentEvent.marketing_state(contact)).to eq(:opted_out)
    end
  ensure
    InstallationConfig.where(name: 'WADESK_OPT_OUT_KEYWORDS').delete_all
    GlobalConfig.clear_cache
  end
end
