require 'rails_helper'

RSpec.describe 'Super Admin WhatsApp Web numbers', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:shop) { create(:account, name: 'Shop Co').tap { |a| a.enable_features!('whatsapp_web') } }
  let(:clinic) { create(:account, name: 'Clinic Co').tap { |a| a.enable_features!('whatsapp_web') } }
  let(:numbers) do
    [
      [shop, 'Shop Sales', '+911111111111', { 'state' => 'connected', 'me' => { 'phone' => '+911111111111' } }],
      [shop, 'Shop Support', '+912222222222', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' }],
      [clinic, 'Clinic Front Desk', '+913333333333', nil],
      [clinic, 'Clinic Billing', '+914444444444', { 'state' => 'failed', 'reason' => 'number_mismatch', 'me' => { 'phone' => '+919999999999' } }]
    ]
  end

  # Connection states are written the way the engine webhook writes them; the Clinic Front Desk number was never linked.
  before do
    numbers.each do |account, inbox_name, phone, update|
      channel = create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: phone, provider_config: {}, sync_templates: false)
      channel.inbox.update!(name: inbox_name)
      WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform if update
    end
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

      it 'lists every WhatsApp Web number with its account, state and reason' do
        get '/super_admin/whatsapp_web_numbers'

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Shop Cloud API')
        expect(response.body).to include("href=\"/super_admin/accounts/#{shop.id}\"", "##{clinic.id} Clinic Co", '+911111111111', 'Connected')
        expect(response.body).to include('Logged out', 'Removed from the phone&#39;s Linked devices', 'Never linked')
        expect(response.body).to include('Could not link', 'A phone with a different number was linked', 'Linked phone: +919999999999')
      end

      it 'marks the number unlinked from the phone as needing a re-link and lists it before connected ones' do
        get '/super_admin/whatsapp_web_numbers'

        body = response.body
        expect(body.scan('Needs re-link').size).to eq(1)
        expect(body.index('Shop Support')).to be < body.index('Needs re-link')
        expect(body.index('Needs re-link')).to be < body.index('Clinic Front Desk')
        expect(['Shop Support', 'Clinic Front Desk', 'Clinic Billing'].map { |name| body.index(name) }).to all(be < body.index('Shop Sales'))
      end

      it 'summarises the totals' do
        get '/super_admin/whatsapp_web_numbers'

        expect(response.body).to match(%r{Total <strong[^>]*>4</strong>})
          .and match(%r{Connected <strong[^>]*>1</strong>})
          .and match(%r{Needs attention <strong[^>]*>3</strong>})
      end

      it 'filters to numbers that need attention or are connected' do
        get '/super_admin/whatsapp_web_numbers', params: { filter: 'attention' }
        expect(response.body).to include('Shop Support', 'Clinic Front Desk', 'Clinic Billing')
        expect(response.body).not_to include('Shop Sales')

        get '/super_admin/whatsapp_web_numbers', params: { filter: 'connected' }
        expect(response.body).to include('Shop Sales')
        expect(response.body).not_to include('Shop Support', 'Clinic Front Desk', 'Clinic Billing')
      end

      it 'loads inboxes and accounts in one query each' do
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get '/super_admin/whatsapp_web_numbers' }

        expect(queries.grep(/FROM "inboxes"/).size).to eq(1)
        expect(queries.grep(/FROM "accounts"/).size).to eq(1)
      end

      it 'is linked from the Super Admin navigation' do
        get '/super_admin/instance_status'
        expect(response.body).to include('href="http://www.example.com/super_admin/whatsapp_web_numbers"', 'WhatsApp Web Numbers')
      end
    end
  end
end
