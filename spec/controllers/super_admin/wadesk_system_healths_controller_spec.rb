require 'rails_helper'

# WaDesk: the operator console's System health page (CR-004).
RSpec.describe 'Super Admin WaDesk system health', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:env) do
    { 'WADESK_ENGINE_URL' => 'http://engine:4000', 'WADESK_ENGINE_API_TOKEN' => 'engine-secret-token-123',
      'SMTP_ADDRESS' => 'smtp.example.com', 'SMTP_PASSWORD' => 'smtp-secret-password', 'MAILER_SENDER_EMAIL' => 'WaDesk <hello@wadesk.example>' }
  end
  let(:stats) { instance_double(Sidekiq::Stats, enqueued: 3, scheduled_size: 12, retry_size: 1, dead_size: 4) }
  let(:workers) { 1 }
  let(:page) { Nokogiri::HTML(response.body) }

  def card(key)
    page.at_css("[data-check='#{key}']")
  end

  it 'is only for super admins' do
    get '/super_admin/wadesk_system_health'
    expect(response).to redirect_to('/super_admin/sign_in')

    sign_in(create(:user, role: :administrator), scope: :user)
    get '/super_admin/wadesk_system_health'
    expect(response).to redirect_to('/super_admin/sign_in')
  end

  context 'when signed in as a super admin' do
    before do
      sign_in(super_admin, scope: :super_admin)
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(instance_double(Sidekiq::ProcessSet, size: workers))
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context)
        .and_return(instance_double(ActiveRecord::MigrationContext, needs_migration?: false))
      stub_request(:get, 'http://engine:4000/health')
        .to_return(status: 200, body: { status: 'ok' }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'says everything is running when every part answers, with one plain card per part' do
      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(response).to have_http_status(:success)
      expect(page.at_css('[data-banner="ok"]').text).to include('Everything is running')
      expect(page.css('[data-check]').map { |c| [c['data-check'], c['data-status']] })
        .to eq([%w[app ok], %w[database ok], %w[redis ok], %w[whatsapp_engine ok], %w[email ok], %w[background_jobs ok]])
      expect(page.css('[data-check] h2').map(&:text)).to eq(['App', 'Database', 'Redis', 'WhatsApp engine', 'Email', 'Background jobs'])
    end

    it 'describes each part in plain words, with versions, memory, sender and job counts' do
      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:app).text).to include("Version #{Chatwoot.config[:version]}", 'database is up to date')
      expect(card(:redis).text).to include('Memory used:')
      expect(card(:email).text).to include('Emails are sent from hello@wadesk.example')
      expect(card(:background_jobs).text.squish)
        .to include('sending messages and emails, talking to WhatsApp',
                    '3 waiting · 12 scheduled for later · 1 retrying after an error · 4 failed for good')
      expect(page.css('a').pluck('href')).not_to include('/monitoring/sidekiq')
    end

    it 'never shows secrets or server addresses' do
      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(response.body).not_to include('engine-secret-token-123', 'smtp-secret-password', 'http://engine:4000', 'smtp.example.com',
                                           ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end

    it 'counts WhatsApp Web numbers and links those needing attention' do
      account = create(:account).tap { |a| a.enable_features!('whatsapp_web') }
      [{ 'state' => 'connected', 'me' => { 'phone' => '911111111111' } }, { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' }]
        .each_with_index do |update, index|
          channel = create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: "+91999999999#{index}",
                                              provider_config: {}, sync_templates: false)
          WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform
        end

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      numbers = card(:whatsapp_engine).at_css('[data-numbers]')
      connected = Channel::Whatsapp.whatsapp_web_connected.count
      attention = Channel::Whatsapp.whatsapp_web_needing_attention.count
      expect(numbers.text.squish).to include("#{connected} #{'number'.pluralize(connected)} connected",
                                             "#{attention} need#{'s' if attention == 1} attention")
      expect(numbers.css('a').pluck('href')).to include('/super_admin/whatsapp_web_numbers?filter=attention', '/super_admin/whatsapp_web_numbers')
    end

    it 'flags an engine that is not answering in time, and names it in the banner' do
      stub_request(:get, 'http://engine:4000/health').to_timeout

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(response).to have_http_status(:success)
      expect(card(:whatsapp_engine)['data-status']).to eq('bad')
      expect(card(:whatsapp_engine).text).to include('The WhatsApp engine is not answering')
      expect(page.at_css('[data-banner="attention"]').text.squish).to include('1 part needs attention: WhatsApp engine')
      expect(page.at_css('[data-banner="ok"]')).to be_nil
    end

    it 'flags an engine whose database is down' do
      stub_request(:get, 'http://engine:4000/health')
        .to_return(status: 503, body: { status: 'unavailable', database: 'down' }.to_json, headers: { 'Content-Type' => 'application/json' })

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:whatsapp_engine)['data-status']).to eq('bad')
      expect(card(:whatsapp_engine).text).to include('cannot reach its database')
    end

    it 'flags an engine that answers with an error' do
      stub_request(:get, 'http://engine:4000/health').to_return(status: 500, body: 'boom')

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:whatsapp_engine)['data-status']).to eq('bad')
      expect(card(:whatsapp_engine).text).to include('answered with an error')
    end

    it 'says so when the engine is not set up' do
      with_modified_env(env.merge('WADESK_ENGINE_URL' => nil)) { get '/super_admin/wadesk_system_health' }

      expect(card(:whatsapp_engine)['data-status']).to eq('warn')
      expect(card(:whatsapp_engine).text).to include('The WhatsApp engine is not set up')
      expect(a_request(:get, 'http://engine:4000/health')).not_to have_been_made
    end

    it 'warns when no email server or sender is set up' do
      with_modified_env(env.merge('SMTP_ADDRESS' => nil, 'MAILER_SENDER_EMAIL' => nil)) { get '/super_admin/wadesk_system_health' }

      expect(card(:email)['data-status']).to eq('warn')
      expect(card(:email).text).to include('No email server is set up', 'No sender address is set')
    end

    it 'flags Redis when it is not answering' do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:redis)['data-status']).to eq('bad')
      expect(card(:redis).text).to include('Redis is not answering')
    end

    it 'flags the database when it is not answering' do
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_call_original
      allow(ActiveRecord::Base.connection).to receive(:select_value).with(/pg_database_size/).and_raise(ActiveRecord::ConnectionNotEstablished)

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:database)['data-status']).to eq('bad')
      expect(card(:database).text).to include('The database is not answering')
    end

    it 'flags an app whose database update (migrations) was not run' do
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context)
        .and_return(instance_double(ActiveRecord::MigrationContext, needs_migration?: true))

      with_modified_env(env) { get '/super_admin/wadesk_system_health' }

      expect(card(:app)['data-status']).to eq('bad')
      expect(card(:app).text).to include('database update (migrations)')
    end

    context 'with many jobs failing' do
      let(:stats) { instance_double(Sidekiq::Stats, enqueued: 0, scheduled_size: 0, retry_size: 30, dead_size: 0) }

      it 'warns about background jobs' do
        with_modified_env(env) { get '/super_admin/wadesk_system_health' }

        expect(card(:background_jobs)['data-status']).to eq('warn')
        expect(card(:background_jobs).text).to include('Many jobs are failing')
        expect(page.at_css('[data-banner="attention"]').text).to include('Background jobs')
      end
    end

    context 'with many jobs failed for good' do
      let(:stats) { instance_double(Sidekiq::Stats, enqueued: 0, scheduled_size: 0, retry_size: 0, dead_size: 100) }

      it 'warns about background jobs' do
        with_modified_env(env) { get '/super_admin/wadesk_system_health' }

        expect(card(:background_jobs)['data-status']).to eq('warn')
      end
    end

    context 'without a background worker' do
      let(:workers) { 0 }

      it 'says background work has stopped' do
        with_modified_env(env) { get '/super_admin/wadesk_system_health' }

        expect(card(:background_jobs)['data-status']).to eq('bad')
        expect(card(:background_jobs).text).to include('No background worker is running')
      end
    end
  end
end
