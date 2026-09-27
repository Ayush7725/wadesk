require 'rails_helper'

RSpec.describe SuperAdmin::WadeskConsoleHelper do
  let(:channel) { build(:channel_whatsapp, provider: 'baileys', provider_config: {}) }

  it 'describes stored WhatsApp Web states in plain words' do
    channel.provider_config = { 'connection_state' => 'logged_out', 'connection_reason' => 'unlinked_from_phone' }

    expect(helper.whatsapp_web_state(channel)).to eq(label: 'Logged out', tone: :bad, reason: 'Removed from the phone\'s Linked devices')
  end

  it 'treats a number without a state as never linked' do
    expect(helper.whatsapp_web_state(channel)).to eq(label: 'Never linked', tone: :mute, reason: nil)
  end

  it 'renders a pill with the label' do
    expect(helper.console_pill('Connected', :ok)).to include('Connected', 'bg-n-teal-3')
  end
end
