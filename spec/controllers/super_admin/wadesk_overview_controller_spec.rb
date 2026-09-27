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
                             ['WhatsApp numbers', '/super_admin/whatsapp_web_numbers'], ['Chatwoot admin', '/super_admin/chatwoot'])
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
end
