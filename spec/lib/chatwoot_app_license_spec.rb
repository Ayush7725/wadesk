require 'rails_helper'

# WaDesk keeps Chatwoot's MIT notice: the rebrand changes what users see, never the LICENSE file (enterprise audit §7).
RSpec.describe ChatwootApp do
  let(:license) { described_class.root.join('LICENSE').read }

  it 'keeps the Chatwoot copyright line and the MIT permission notice in LICENSE' do
    expect(license).to match(/^Copyright \(c\) 2017-\d{4} Chatwoot Inc\.$/)
    expect(license).to include('Permission is hereby granted, free of charge, to any person obtaining a copy',
                               'The above copyright notice and this permission notice shall be included in',
                               'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND')
  end
end
