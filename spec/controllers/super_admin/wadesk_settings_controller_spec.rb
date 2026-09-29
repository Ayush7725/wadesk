require 'rails_helper'

# WaDesk: the operator console's installation-wide Settings page (CR-004).
RSpec.describe 'Super Admin WaDesk settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:signup_params) { { account_name: 'New Client', email: 'owner@newclient.example', user_full_name: 'Owner', password: 'Password1!' } }

  def page
    Nokogiri::HTML(response.body)
  end

  def config_value(name)
    InstallationConfig.find_by(name: name)&.value
  end

  # GlobalConfig caches in Redis, which the test transaction does not roll back.
  around do |example|
    GlobalConfig.clear_cache
    example.run
    GlobalConfig.clear_cache
  end

  it 'is only for super admins' do
    get '/super_admin/wadesk_settings'
    expect(response).to redirect_to('/super_admin/sign_in')

    sign_in(create(:user, role: :administrator), scope: :user)
    patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1' } }
    expect(response).to redirect_to('/super_admin/sign_in')
    expect(GlobalConfigService.account_signup_enabled?).to be(false)
  end

  context 'when signed in as a super admin' do
    before do
      sign_in(super_admin, scope: :super_admin)
      InstallationConfig.find_or_initialize_by(name: 'ENABLE_ACCOUNT_SIGNUP').update!(value: false, locked: false)
    end

    it 'turns sign-ups on and off where the sign-up check reads them' do
      post '/api/v1/accounts', params: signup_params, as: :json
      expect(response).to have_http_status(:not_found)

      sign_in(super_admin, scope: :super_admin) # the API request above replaced the session
      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1' } }

      expect(GlobalConfigService.account_signup_enabled?).to be(true)
      post '/api/v1/accounts', params: signup_params, as: :json
      expect(response).not_to have_http_status(:not_found)

      sign_in(super_admin, scope: :super_admin)
      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '0' } }

      expect(GlobalConfigService.account_signup_enabled?).to be(false)
      post '/api/v1/accounts', params: signup_params.merge(email: 'other@newclient.example'), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'shows the saved switch with a save notice' do
      get '/super_admin/wadesk_settings'
      expect(page.at_css('#settings_ENABLE_ACCOUNT_SIGNUP')['checked']).to be_nil
      expect(page.at_css('#settings_ENABLE_ACCOUNT_SIGNUP-description').text).to include('create a new client account')

      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1' } }

      expect(response).to redirect_to('/super_admin/wadesk_settings')
      follow_redirect!
      expect(page.at_css('[role="status"]').text).to include('Settings saved')
      expect(page.at_css('#settings_ENABLE_ACCOUNT_SIGNUP')['checked']).to eq('checked')
    end

    it 'keeps a legacy "api_only" sign-up value when the switch is saved unchanged' do
      InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP').update!(value: 'api_only')

      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1' } }

      expect(config_value('ENABLE_ACCOUNT_SIGNUP')).to eq('api_only')
    end

    it 'never writes settings outside the allow-list' do
      secret = config_value('FB_APP_SECRET')

      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1', FB_APP_SECRET: 'hijacked', DEPLOYMENT_ENV: 'cloud' } }

      expect(response).to redirect_to('/super_admin/wadesk_settings')
      expect(config_value('FB_APP_SECRET')).to eq(secret)
      expect(InstallationConfig.find_by(name: 'DEPLOYMENT_ENV')&.value).not_to eq('cloud')
    end

    it 'rejects a sign-up value other than on or off' do
      patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: 'api_only' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(config_value('ENABLE_ACCOUNT_SIGNUP')).to be(false)
    end

    context 'when Chatwoot\'s enterprise edition would reset the brand every night' do
      before { allow(ChatwootHub).to receive(:pricing_plan).and_return('community') }

      it 'shows the brand read-only and explains why, and ignores submitted brand values' do
        allow(ChatwootApp).to receive(:enterprise?).and_return(true)
        name = config_value('INSTALLATION_NAME')

        get '/super_admin/wadesk_settings'

        expect(page.at_css('[data-brand-locked]').text).to include('DISABLE_ENTERPRISE=true')
        expect(page.at_css('input[name="settings[INSTALLATION_NAME]"]')).to be_nil

        patch '/super_admin/wadesk_settings', params: { settings: { ENABLE_ACCOUNT_SIGNUP: '0', INSTALLATION_NAME: 'WaDesk' } }

        expect(config_value('INSTALLATION_NAME')).to eq(name)
      end
    end

    context 'without Chatwoot\'s enterprise edition' do
      before do
        allow(ChatwootApp).to receive(:enterprise?).and_return(false)
        InstallationConfig.find_or_initialize_by(name: 'BRAND_NAME').update!(value: 'Chatwoot')
        InstallationConfig.find_or_initialize_by(name: 'TERMS_URL').update!(value: 'https://www.chatwoot.com/terms-of-service')
      end

      let(:brand) do
        { INSTALLATION_NAME: 'WaDesk', BRAND_NAME: 'WaDesk', BRAND_URL: 'https://wadesk.example', WIDGET_BRAND_URL: 'https://wadesk.example',
          TERMS_URL: 'https://wadesk.example/terms', PRIVACY_URL: 'https://wadesk.example/privacy', LOGO: '/brand-assets/wadesk.svg',
          LOGO_DARK: 'https://cdn.wadesk.example/logo-dark.svg', LOGO_THUMBNAIL: '/brand-assets/wadesk-square.png' }
      end

      it 'shows the current brand, each with what it affects' do
        get '/super_admin/wadesk_settings'

        expect(response).to have_http_status(:success)
        expect(page.at_css('[data-brand-locked]')).to be_nil
        expect(page.at_css('input[name="settings[BRAND_NAME]"]')['value']).to eq('Chatwoot')
        expect(page.at_css('input[name="settings[TERMS_URL]"]')['value']).to eq('https://www.chatwoot.com/terms-of-service')
        expect(page.at_css('label[for="settings_BRAND_NAME"]').text).to eq('Brand name')
        expect(page.at_css('#settings_BRAND_NAME-hint').text).to include('emails')
      end

      it 'saves the brand where the apps read it' do
        InstallationConfig.where(name: 'INSTALLATION_NAME').delete_all

        patch '/super_admin/wadesk_settings', params: { settings: brand.merge(ENABLE_ACCOUNT_SIGNUP: '0') }

        expect(response).to redirect_to('/super_admin/wadesk_settings')
        expect(GlobalConfig.get(*brand.keys.map(&:to_s))).to eq(brand.stringify_keys)
        expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').locked).to be(true)
      end

      it 'rejects invalid addresses and saves nothing' do
        patch '/super_admin/wadesk_settings',
              params: { settings: { ENABLE_ACCOUNT_SIGNUP: '1', BRAND_NAME: 'WaDesk', TERMS_URL: 'javascript:alert(1)',
                                    BRAND_URL: 'https://user:pass@wadesk.example', LOGO: '//evil.example/logo.svg' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#settings_TERMS_URL')['aria-invalid']).to eq('true')
        expect(page.at_css('#settings_TERMS_URL-error').text).to include('must be a web address')
        expect(%w[BRAND_URL LOGO].map { |key| page.at_css("#settings_#{key}-error")&.text }).to all(include('must be a web address'))
        expect(page.at_css('#settings_BRAND_NAME')['value']).to eq('WaDesk')
        expect(config_value('BRAND_NAME')).to eq('Chatwoot')
        expect(config_value('ENABLE_ACCOUNT_SIGNUP')).to be(false)
      end

      it 'saves the form as shipped: no brand links and terms and privacy pages on this server' do
        shipped = ConfigLoader.new.general_configs.to_h { |config| [config['name'], config['value']] }.slice(*brand.keys.map(&:to_s))
        expect(shipped).to include('BRAND_URL' => '', 'WIDGET_BRAND_URL' => '', 'TERMS_URL' => '/terms.html', 'PRIVACY_URL' => '/privacy.html')

        get '/super_admin/wadesk_settings'
        expect(page.at_css('#settings_BRAND_URL')['required']).to be_nil
        expect(page.at_css('#settings_TERMS_URL')['type']).to eq('text')
        expect(page.at_css('#settings_BRAND_NAME')['required']).to eq('required')

        patch '/super_admin/wadesk_settings', params: { settings: shipped.merge('ENABLE_ACCOUNT_SIGNUP' => '0') }

        expect(response).to redirect_to('/super_admin/wadesk_settings')
        expect(GlobalConfig.get(*shipped.keys)).to eq(shipped)
      end

      it 'accepts a page on this server only for the terms and privacy links' do
        patch '/super_admin/wadesk_settings', params: { settings: { TERMS_URL: '/legal/terms.html', BRAND_URL: '/about' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#settings_TERMS_URL-error')).to be_nil
        expect(page.at_css('#settings_BRAND_URL-error').text).to include('must be a web address (https://…).')
      end

      it 'rejects an empty brand name' do
        patch '/super_admin/wadesk_settings', params: { settings: { BRAND_NAME: ' ' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#settings_BRAND_NAME-error').text).to include('cannot be empty')
        expect(config_value('BRAND_NAME')).to eq('Chatwoot')
      end
    end
  end
end
