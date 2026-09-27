require 'rails_helper'

RSpec.describe 'Super Admin WhatsApp Web numbers', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:shop) { create(:account, name: 'Shop Co').tap { |a| a.enable_features!('whatsapp_web') } }
  let(:clinic) { create(:account, name: 'Clinic Co').tap { |a| a.enable_features!('whatsapp_web') } }
  let(:numbers) do
    [
      [shop, 'Shop Sales', '+911111111111', { 'state' => 'connected', 'me' => { 'phone' => '911111111111' } }],
      [shop, 'Shop Support', '+912222222222', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' }],
      [clinic, 'Clinic Front Desk', '+913333333333', nil],
      [clinic, 'Clinic Billing', '+914444444444', { 'state' => 'failed', 'reason' => 'number_mismatch', 'me' => { 'phone' => '919999999999' } }]
    ]
  end

  def html = Nokogiri::HTML(response.body)
  def rows = html.css('tbody tr').map { |row| row.css('td').map { |cell| cell.text.squish } }
  def inboxes = rows.map { |row| row[1] }

  def create_number(account, inbox_name, phone, update)
    channel = create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: phone, provider_config: {}, sync_templates: false)
    channel.inbox.update!(name: inbox_name)
    WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform if update
  end

  # Connection states are written the way the engine webhook writes them; the Clinic Front Desk number was never linked.
  before do
    numbers.each { |number| create_number(*number) }
    cloud = create(:channel_whatsapp, account: shop, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    cloud.inbox.update!(name: 'Shop Cloud API')
  end

  describe 'GET /super_admin/whatsapp_web_numbers' do
    it 'redirects visitors who are not signed in as a super admin' do
      get '/super_admin/whatsapp_web_numbers'
      expect(response).to have_http_status(:redirect)

      sign_in(create(:user, account: shop, role: :administrator), scope: :user)
      get '/super_admin/whatsapp_web_numbers'
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include('Shop Sales')
    end

    context 'when signed in as a super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'opens on the numbers that need attention, in the console, with their client, state and what happened' do
        get '/super_admin/whatsapp_web_numbers'

        expect(response).to have_http_status(:success)
        expect(html.at_css('aside a[aria-current="page"]').text.squish).to start_with('WhatsApp numbers')
        support, front_desk, billing = rows
        expect(rows.size).to eq(3)
        expect(support).to eq(['+912222222222', 'Shop Co Shop Support', 'Logged out Needs re-link', 'Removed from the phone\'s Linked devices',
                               'less than a minute ago', 'QR code'])
        expect(front_desk).to eq(['+913333333333', 'Clinic Co Clinic Front Desk', 'Never linked', 'Nobody has linked a phone yet', '—Never',
                                  'QR code'])
        expect(billing).to eq(['+914444444444 Scanned by +919999999999', 'Clinic Co Clinic Billing', 'Could not link',
                               'A phone with a different number was linked', 'less than a minute ago', 'QR code'])
        expect(response.body).not_to include('Shop Sales', 'Shop Cloud API')
      end

      it 'links every number to its client page' do
        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all' }

        links = html.css('tbody tr').map { |row| row.at_css('a')['href'] }
        expect(links).to eq(["/super_admin/wadesk_clients/#{shop.id}/edit", "/super_admin/wadesk_clients/#{clinic.id}/edit",
                             "/super_admin/wadesk_clients/#{clinic.id}/edit", "/super_admin/wadesk_clients/#{shop.id}/edit"])
      end

      it 'lists every number with the ones needing attention first, and marks the chosen filter' do
        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all' }

        expect(inboxes).to eq(['Shop Co Shop Support', 'Clinic Co Clinic Front Desk', 'Clinic Co Clinic Billing', 'Shop Co Shop Sales'])
        expect(rows.last[2]).to eq('Connected')
        expect(rows.last[0]).to eq('+911111111111') # linked with its own phone
        filters = html.css('nav[aria-label="Filter numbers"] a').map { |link| [link.text.squish, link['aria-current']] }
        expect(filters).to eq([['Need attention 3', nil], ['Connected 1', nil], ['All 4', 'true']])
      end

      it 'filters to connected numbers' do
        get '/super_admin/whatsapp_web_numbers', params: { filter: 'connected' }

        expect(inboxes).to eq(['Shop Co Shop Sales'])
      end

      it 'finds a number typed with spaces or without the plus' do
        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all', search: '91 44444 44444' }
        expect(inboxes).to eq(['Clinic Co Clinic Billing'])

        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all', search: '+9111111' }
        expect(inboxes).to eq(['Shop Co Shop Sales'])
      end

      it 'finds numbers by part of the client or inbox name, within the chosen filter' do
        get '/super_admin/whatsapp_web_numbers', params: { search: 'clinic' }
        expect(inboxes).to eq(['Clinic Co Clinic Front Desk', 'Clinic Co Clinic Billing'])
        expect(html.at_css('input[type="search"][name="search"]')['value']).to eq('clinic')
        expect(html.at_css('input[type="hidden"][name="filter"]')['value']).to eq('attention')

        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all', search: 'SALES' }
        expect(inboxes).to eq(['Shop Co Shop Sales'])
      end

      it 'says when a search finds nothing in the filter and offers to search all numbers' do
        get '/super_admin/whatsapp_web_numbers', params: { search: 'Sales' }

        expect(rows).to be_empty
        empty = html.at_css('[data-empty="numbers"]')
        expect(empty.text.squish).to eq('No number matches “Sales” in Need attention. Search all numbers')
        expect(empty.at_css('a')['href']).to eq('/super_admin/whatsapp_web_numbers?filter=all&search=Sales')
      end

      it 'loads inboxes and accounts in one query each, however many numbers there are' do
        count_queries = lambda do
          queries = []
          callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
          ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
            get '/super_admin/whatsapp_web_numbers', params: { filter: 'all' }
          end
          queries
        end
        count_queries.call # warms up one-off lookups
        queries = count_queries.call
        expect(queries.grep(/FROM "inboxes"/).size).to eq(1)
        expect(queries.grep(/FROM "accounts"/).size).to eq(1)

        other = create(:account, name: 'Other Co').tap { |a| a.enable_features!('whatsapp_web') }
        3.times { |i| create_number(other, "Other #{i}", "+91555555555#{i}", { 'state' => 'logged_out', 'reason' => 'forbidden' }) }
        expect(count_queries.call.size).to eq(queries.size)
      end

      it 'shows 50 numbers a page, keeping the filter across pages' do
        48.times { |i| create_number(clinic, "Clinic extra #{i}", "+9177777#{i.to_s.rjust(5, '0')}", nil) }

        get '/super_admin/whatsapp_web_numbers', params: { search: 'clinic' }
        expect(rows.size).to eq(50)
        expect(html.at_css('nav[aria-label="Pages"]')).to be_nil

        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all' }
        expect(rows.size).to eq(50)
        pages = html.at_css('nav[aria-label="Pages"]')
        expect(pages.text.squish).to eq('1–50 of 52 Next')
        expect(pages.at_css('a[rel="next"]')['href']).to eq('/super_admin/whatsapp_web_numbers?filter=all&page=2')

        get '/super_admin/whatsapp_web_numbers', params: { filter: 'all', page: 2 }
        expect(inboxes).to eq(['Clinic Co Clinic extra 47', 'Shop Co Shop Sales'])
        expect(html.at_css('nav[aria-label="Pages"]').text.squish).to eq('51–52 of 52 Previous')
      end

      it 'is linked from Chatwoot\'s own Super Admin navigation' do
        get '/super_admin/instance_status'
        expect(response.body).to include('href="http://www.example.com/super_admin/whatsapp_web_numbers"', 'WhatsApp Web Numbers')
      end
    end
  end

  context 'when every number is connected' do
    let(:numbers) { [[shop, 'Shop Sales', '+911111111111', { 'state' => 'connected', 'me' => { 'phone' => '911111111111' } }]] }

    before { sign_in(super_admin, scope: :super_admin) }

    it 'says so instead of showing an empty table' do
      get '/super_admin/whatsapp_web_numbers'

      expect(html.css('table')).to be_empty
      expect(html.at_css('[data-empty="numbers"]').text.squish).to eq('Nothing here. Every number is connected.')
    end
  end
end
