require 'rails_helper'

# WaDesk: the operator console is Super Admin's home page (ADR-0008).
RSpec.describe 'Super Admin WaDesk console', type: :request do
  let(:super_admin) { create(:super_admin, name: 'Riya Operator') }
  let(:account) { create(:account, name: 'Sharma Traders').tap { |a| a.enable_features!('whatsapp_web') } }

  def whatsapp_web_number(phone, update)
    channel = create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: phone, provider_config: {}, sync_templates: false)
    WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform if update
    channel
  end

  it 'sends signed-out visitors and account users to the Super Admin login' do
    get '/super_admin'
    expect(response).to redirect_to('/super_admin/sign_in')

    sign_in(create(:user, account: account, role: :administrator), scope: :user)
    get '/super_admin'
    expect(response).to redirect_to('/super_admin/sign_in')
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'opens the console with its navigation and the operator' do
      get '/super_admin'

      expect(response).to have_http_status(:success)
      page = Nokogiri::HTML(response.body)
      nav = page.css('aside[aria-label="Operator console"] a').map { |link| [link.text.squish, link['href']] }
      expect(nav).to include(['Overview', '/super_admin'], ['Clients', '/super_admin/wadesk_clients'],
                             ['WhatsApp numbers', '/super_admin/whatsapp_web_numbers'], ['Users', '/super_admin/wadesk_users'],
                             ['System health', '/super_admin/wadesk_system_health'], ['Settings', '/super_admin/wadesk_settings'])
      # One app: Chatwoot's raw admin and developer tools are not linked from the console (CR-004).
      expect(nav.map(&:last)).not_to include('/super_admin/chatwoot', '/monitoring/sidekiq', '/super_admin/instance_status')
      expect(page.at_css('aside a[aria-current="page"]').text.squish).to eq('Overview')
      expect(page.at_css('aside').text).to include('Riya Operator', 'WaDesk', 'Operator Console')
    end

    it 'counts numbers that need attention in the sidebar, including never-linked ones' do
      whatsapp_web_number('+911111111111', { 'state' => 'connected', 'me' => { 'phone' => '911111111111' } })
      whatsapp_web_number('+912222222222', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' })
      whatsapp_web_number('+913333333333', nil)

      get '/super_admin'

      link = Nokogiri::HTML(response.body).at_css('aside a[href="/super_admin/whatsapp_web_numbers"]')
      expect(link.text.squish).to eq('WhatsApp numbers 2')
    end

    it 'keeps Chatwoot\'s own dashboard one click away, linking back to the console' do
      get '/super_admin/chatwoot'

      expect(response).to have_http_status(:success)
      console_links = Nokogiri::HTML(response.body).css('a[href$="/super_admin"]').map { |link| link.text.squish }
      expect(console_links).to include('WaDesk console')
    end
  end

  context 'with several clients on different plans' do
    let(:shop) { create(:account, name: 'Shop Co') }
    let(:clinic) { create(:account, name: 'Clinic Co') }
    let(:jewels) { create(:account, name: 'Jewels Co') }
    let(:coaching) { create(:account, name: 'Coaching Co') }
    let(:nimbus) { create(:account, name: 'Nimbus Co', status: :suspended) }
    let(:plans) do
      { shop => %w[whatsapp_web whatsapp_official], clinic => %w[whatsapp_web], coaching => %w[whatsapp_web], jewels => %w[whatsapp_official],
        nimbus => [] }
    end
    let(:html) { Nokogiri::HTML(response.body) }
    let(:attention_rows) { html.css('[data-section="attention"] li').map { |row| row.text.squish } }

    def create_number(account, inbox_name, phone, update)
      channel = create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: phone, provider_config: {}, sync_templates: false)
      channel.inbox.update!(name: inbox_name)
      WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform if update
    end

    def count_queries
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get '/super_admin' }
      queries
    end

    before do
      Account.where.not(id: plans.keys).delete_all # the counts cover every account; keep only this example's clients
      plans.each do |account, features|
        account.disable_features('whatsapp_web', 'whatsapp_official')
        account.enable_features!(*features)
      end
      create_number(shop, 'Shop Sales', '+911111111111', { 'state' => 'connected', 'me' => { 'phone' => '911111111111' } })
      create_number(shop, 'Shop Support', '+912222222222', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' })
      create_number(clinic, 'Clinic Front Desk', '+913333333333', nil)
      create_number(clinic, 'Clinic Billing', '+914444444444',
                    { 'state' => 'failed', 'reason' => 'number_mismatch', 'me' => { 'phone' => '919999999999' } })
      cloud = create(:channel_whatsapp, account: jewels, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      cloud.inbox.update!(name: 'Jewels Cloud API')
      sign_in(super_admin, scope: :super_admin)
    end

    it 'summarises clients and their WhatsApp Web numbers, leaving WhatsApp Cloud inboxes out' do
      get '/super_admin'

      cards = html.css('[data-summary]').to_h { |card| [card['data-summary'], card.text.squish] }
      expect(cards).to eq(
        'clients' => 'Active clients 4 1 suspended',
        'numbers' => 'WhatsApp Web numbers 4 across 2 clients',
        'connected' => 'Connected 1 / 4 1 of 4',
        'attention' => 'Need attention 3 logged out, failed or waiting'
      )
      expect(html.at_css('[data-summary="connected"] progress').attributes.transform_values(&:value)).to include('value' => '1', 'max' => '4')
      expect(html.at_css('[data-summary="attention"] strong')['class']).to include('text-n-ruby-11')
    end

    it 'lists the numbers that need attention in plain words, each linking to its client' do
      get '/super_admin'

      expect(attention_rows).to eq([
                                     'Shop Co · Shop Support +912222222222 Removed from the phone\'s Linked devices Logged out',
                                     'Clinic Co · Clinic Front Desk +913333333333 Nobody has linked a phone yet Never linked',
                                     'Clinic Co · Clinic Billing +914444444444 A phone with a different number was linked Could not link'
                                   ])
      links = html.css('[data-section="attention"] li a').map { |link| link['href'] }
      expect(links).to eq(["/super_admin/wadesk_clients/#{shop.id}/edit", "/super_admin/wadesk_clients/#{clinic.id}/edit",
                           "/super_admin/wadesk_clients/#{clinic.id}/edit"])
      expect(html.at_css('[data-section="attention"] a[href="/super_admin/whatsapp_web_numbers"]').text).to eq('See all numbers')
      expect(response.body).not_to include('Shop Sales', 'Jewels Cloud API')
    end

    it 'shows the first few numbers needing attention and links to the rest' do
      9.times { |i| create_number(clinic, "Clinic #{i}", "+91555555555#{i}", { 'state' => 'logged_out', 'reason' => 'forbidden' }) }

      get '/super_admin'

      expect(attention_rows.size).to eq(8)
      more = html.at_css('[data-section="attention"] a[href="/super_admin/whatsapp_web_numbers?filter=attention"]')
      expect(more.text).to eq('See all 12 numbers that need attention')
    end

    it 'counts clients on each plan and links to Clients' do
      get '/super_admin'

      plan_rows = html.css('[data-section="plans"] [data-plan]').map { |row| row.text.squish }
      expect(plan_rows).to eq(['Both 1', 'Web only 2', 'Official only 1', 'No WhatsApp 1'])
      expect(html.at_css('[data-section="plans"] a[href="/super_admin/wadesk_clients"]').text).to eq('Manage clients')
    end

    it 'says all is well when every number is connected' do
      Channel::Whatsapp.whatsapp_web_needing_attention.find_each do |channel|
        channel.update_column(:provider_config, channel.provider_config.merge('connection_state' => 'connected')) # rubocop:disable Rails/SkipsModelValidations
      end

      get '/super_admin'

      expect(html.css('[data-section="attention"] li')).to be_empty
      expect(html.at_css('[data-empty="attention"]').text.squish).to eq('All good. Every WhatsApp Web number is connected.')
    end

    it 'runs the same queries however many clients and numbers there are' do
      count_queries # warms up one-off lookups
      queries = count_queries
      other = create(:account, name: 'Other Co').tap { |a| a.enable_features!('whatsapp_web') }
      3.times { |i| create_number(other, "Other #{i}", "+91666666666#{i}", nil) }

      expect(count_queries.size).to eq(queries.size)
    end
  end
end
