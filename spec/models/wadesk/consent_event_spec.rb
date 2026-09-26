require 'rails_helper'

RSpec.describe Wadesk::ConsentEvent do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def record(kind, at) = described_class.create!(account: account, contact: contact, kind: kind, source: 'agent', created_at: at)

  it 'is append-only' do
    event = record(:opt_out, Time.current)

    expect { event.update!(kind: :opt_in) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'derives the current marketing state from the latest entry' do
    expect(described_class.marketing_state(contact)).to eq(:unknown)

    record(:opt_in, 2.days.ago)
    expect(described_class.marketing_state(contact)).to eq(:opted_in)

    record(:opt_out, 1.day.ago)
    expect(described_class.marketing_state(contact)).to eq(:opted_out)
  end
end
