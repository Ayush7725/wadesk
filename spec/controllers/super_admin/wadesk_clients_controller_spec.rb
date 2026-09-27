require 'rails_helper'

# WaDesk: the operator manages client plans and the WhatsApp Web daily new-chat limit from Super Admin.
RSpec.describe 'Super Admin WaDesk clients', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Sharma Traders', custom_attributes: { 'brand_info' => { 'name' => 'Sharma' } }) }
  let(:limit_key) { Wadesk::Safety::NewChatLimit::LIMIT_KEY }
  let(:plan_params) { { whatsapp_official: '1', whatsapp_web: '1', daily_new_chats: '' } }

  describe 'access' do
    it 'sends signed-out visitors to the login page' do
      get '/super_admin/wadesk_clients'

      expect(response).to redirect_to('/super_admin/sign_in')
    end

    it 'refuses account users who are not super admins' do
      user = create(:user, account: account, role: :administrator)
      sign_in(user, scope: :user)

      get '/super_admin/wadesk_clients'
      expect(response).to redirect_to('/super_admin/sign_in')

      patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_official: '0') }
      expect(response).to redirect_to('/super_admin/sign_in')
      expect(account.reload.feature_enabled?('whatsapp_official')).to be(true)
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'links the page from the navigation' do
      get '/super_admin'

      link = Nokogiri::HTML(response.body).at_css('a[href$="/super_admin/wadesk_clients"]')
      expect(link.text.squish).to eq('WaDesk Clients')
    end

    describe 'GET /super_admin/wadesk_clients' do
      it 'lists each account with its plan, daily new-chat limit and WhatsApp inbox counts' do
        account.enable_features!('whatsapp_web')
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
        create(:channel_twilio_sms, :whatsapp, account: account)
        create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: {}, sync_templates: false)
        web_only = create(:account, name: 'Gupta Stores', custom_attributes: { limit_key => 50 })
        web_only.disable_features!('whatsapp_official')

        get '/super_admin/wadesk_clients'

        expect(response).to have_http_status(:success)
        rows = Nokogiri::HTML(response.body).css('tbody tr').to_h { |row| [row['data-account-id'].to_i, row.css('td').map { |td| td.text.squish }] }
        expect(rows[account.id].first(8)).to eq([account.id.to_s, 'Sharma Traders', 'active', 'On', 'On', '20 (default)', '2', '1'])
        expect(rows[web_only.id].first(8)).to eq([web_only.id.to_s, 'Gupta Stores', 'active', 'Off', 'Off', '50', '0', '0'])
      end

      it 'finds accounts by name or id' do
        account
        other = create(:account, name: 'Gupta Stores')

        get '/super_admin/wadesk_clients', params: { search: 'sharma' }
        expect(response.body).to include('Sharma Traders')
        expect(response.body).not_to include('Gupta Stores')

        get '/super_admin/wadesk_clients', params: { search: other.id.to_s }
        expect(response.body).to include('Gupta Stores')
        expect(response.body).not_to include('Sharma Traders')
      end
    end

    describe 'GET /super_admin/wadesk_clients/{account_id}/edit' do
      it 'warns that existing inboxes keep working when a plan with inboxes is turned off' do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

        get "/super_admin/wadesk_clients/#{account.id}/edit"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Turning WhatsApp Official off keeps these 1 inbox working')
        expect(response.body).not_to include('Turning WhatsApp Web off')
      end
    end

    describe 'PATCH /super_admin/wadesk_clients/{account_id}' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'turns a plan off while existing inboxes keep working, and the dashboard sees the change' do
        channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_official: '0') }

        expect(response).to redirect_to('/super_admin/wadesk_clients')
        expect(flash[:notice]).to eq('Plan for Sharma Traders updated. Existing WhatsApp Official inboxes keep working; only new ones are blocked.')
        get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
        expect(response.parsed_body['features']).to include('whatsapp_web' => true)
        expect(response.parsed_body['features']).not_to have_key('whatsapp_official')
        channel.reload.update!(provider_config: channel.provider_config.merge('api_key' => 'rotated_key'))
        expect(channel.reload.provider_config['api_key']).to eq('rotated_key')
      end

      it 'turns a plan back on and another off' do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
        account.disable_features!('whatsapp_official')
        account.enable_features!('whatsapp_web')

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_web: '0') }

        expect(flash[:notice]).to eq('Plan for Sharma Traders updated.')
        expect(account.reload.feature_enabled?('whatsapp_official')).to be(true)
        expect(account.feature_enabled?('whatsapp_web')).to be(false)
      end

      it 'sets the daily new-chat limit that WhatsApp Web sending uses, without touching other custom attributes' do
        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(daily_new_chats: '25') }

        expect(account.reload.custom_attributes).to eq('brand_info' => { 'name' => 'Sharma' }, limit_key => 25)
        expect(Wadesk::Safety::NewChatLimit.new(message: instance_double(Message, account: account)).daily_limit).to eq(25)
      end

      it 'clears the limit back to the default when left blank' do
        account.update!(custom_attributes: account.custom_attributes.merge(limit_key => 40))

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params }

        expect(account.reload.custom_attributes).to eq('brand_info' => { 'name' => 'Sharma' })
        expect(Wadesk::Safety::NewChatLimit.new(message: instance_double(Message, account: account)).daily_limit).to eq(20)
      end

      %w[0 -3 abc 5000 2.5].each do |limit|
        it "rejects #{limit.inspect} as a limit and changes nothing" do
          account.update!(custom_attributes: account.custom_attributes.merge(limit_key => 40))

          patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_official: '0', daily_new_chats: limit) }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include('Daily new-chat limit must be a whole number from 1 to 1000, or blank for the default (20).')
          expect(account.reload.custom_attributes[limit_key]).to eq(40)
          expect(account.feature_enabled?('whatsapp_official')).to be(true)
          form = Nokogiri::HTML(response.body)
          expect(form.at_css('input[type=checkbox][name="client[whatsapp_official]"]')['checked']).to be_nil # keeps the operator's choice
          expect(form.at_css('input[type=checkbox][name="client[whatsapp_web]"]')['checked']).to eq('checked')
        end
      end
    end
  end
end
