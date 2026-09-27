require 'rails_helper'

# WaDesk: the operator console's Clients pages: plans, the WhatsApp Web daily new-chat limit and per-client features.
RSpec.describe 'Super Admin WaDesk clients', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Sharma Traders', custom_attributes: { 'brand_info' => { 'name' => 'Sharma' } }) }
  let(:limit_key) { Wadesk::Safety::NewChatLimit::LIMIT_KEY }
  let(:plan_params) { { whatsapp_official: '1', whatsapp_web: '1', daily_new_chats: '' } }

  def whatsapp_web_number(owner, inbox_name, phone, update)
    channel = create(:channel_whatsapp, account: owner, provider: 'baileys', phone_number: phone, provider_config: {}, sync_templates: false)
    channel.inbox.update!(name: inbox_name)
    WhatsappWeb::ConnectionUpdateService.new(channel: channel, payload: update).perform if update
    channel
  end

  def official_inbox(owner, provider)
    create(:channel_whatsapp, account: owner, provider: provider, sync_templates: false, validate_provider_config: false)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  describe 'access' do
    it 'sends signed-out visitors to the login page' do
      get '/super_admin/wadesk_clients'

      expect(response).to redirect_to('/super_admin/sign_in')
    end

    it 'refuses account users who are not super admins' do
      account.enable_features!('campaigns')
      user = create(:user, account: account, role: :administrator)
      sign_in(user, scope: :user)

      get '/super_admin/wadesk_clients'
      expect(response).to redirect_to('/super_admin/sign_in')

      get "/super_admin/wadesk_clients/#{account.id}/edit"
      expect(response).to redirect_to('/super_admin/sign_in')

      patch "/super_admin/wadesk_clients/#{account.id}",
            params: { client: plan_params.merge(whatsapp_official: '0', features: { campaigns: '0', data_import: '1' }) }
      expect(response).to redirect_to('/super_admin/sign_in')
      expect(account.reload.feature_enabled?('whatsapp_official')).to be(true)
      expect(account.feature_enabled?('campaigns')).to be(true)
      expect(account.feature_enabled?('data_import')).to be(false)
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'links the page from Chatwoot\'s admin navigation' do
      get '/super_admin/chatwoot'

      link = page.at_css('a[href$="/super_admin/wadesk_clients"]')
      expect(link.text.squish).to eq('WaDesk Clients')
    end

    describe 'GET /super_admin/wadesk_clients' do
      # Realistic mix: Both / Web only (x2) / Official only / no WhatsApp / a suspended Official client.
      let!(:clients) do
        Account.delete_all # a local test database may hold seeded accounts; the list must show only these
        account.update!(custom_attributes: account.custom_attributes.merge(limit_key => 25))
        account.enable_features!('whatsapp_web')
        official_inbox(account, 'whatsapp_cloud')
        create(:channel_twilio_sms, :whatsapp, account: account)
        whatsapp_web_number(account, 'Sales desk', '+919828074219', { 'state' => 'connected', 'me' => { 'phone' => '919828074219' } })
        whatsapp_web_number(account, 'Support', '+919829011420', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' })

        glow = create(:account, name: 'Glow Dental Clinic')
        glow.disable_features('whatsapp_official')
        glow.enable_features!('whatsapp_web')
        whatsapp_web_number(glow, 'Appointments', '+919922045310', { 'state' => 'connected', 'me' => { 'phone' => '919922045310' } })

        metro = create(:account, name: 'Metro Realty', custom_attributes: { limit_key => 40 })
        metro.disable_features('whatsapp_official')
        metro.enable_features!('whatsapp_web')
        whatsapp_web_number(metro, 'Site visits', '+919811076502', { 'state' => 'failed', 'reason' => 'number_mismatch' })
        whatsapp_web_number(metro, 'Leads', '+919811076511', nil)

        jewels = create(:account, name: 'Jaipur Jewels')
        official_inbox(jewels, 'whatsapp_cloud')
        official_inbox(jewels, 'default')

        blank = create(:account, name: 'Blank Studio')
        blank.disable_features!('whatsapp_official')

        nimbus = create(:account, name: 'Nimbus Travels', status: :suspended)
        official_inbox(nimbus, 'whatsapp_cloud')

        { both: account, glow: glow, metro: metro, jewels: jewels, blank: blank, nimbus: nimbus }
      end

      def rows
        page.css('tbody tr[data-account-id]').to_h { |row| [row['data-account-id'].to_i, row.css('td').map { |td| td.text.squish }] }
      end

      def filter_links
        page.css('nav[aria-label="Filter by plan"] a').map { |link| [link.text.squish, link['aria-current']] }
      end

      it 'lists each client with status, plan, daily new chats, WhatsApp Web numbers needing attention and official inboxes' do
        get '/super_admin/wadesk_clients'

        expect(response).to have_http_status(:success)
        expect(page.at_css('aside a[aria-current="page"]').text.squish).to eq('Clients')
        expect(rows).to eq(
          account.id => ["Sharma Traders ##{account.id}", 'Active', 'Official Web', '25', '2 1 need attention', '2', 'Manage'],
          clients[:glow].id => ["Glow Dental Clinic ##{clients[:glow].id}", 'Active', 'Web', '20 default', '1', '0', 'Manage'],
          clients[:metro].id => ["Metro Realty ##{clients[:metro].id}", 'Active', 'Web', '40', '2 2 need attention', '0', 'Manage'],
          clients[:jewels].id => ["Jaipur Jewels ##{clients[:jewels].id}", 'Active', 'Official', '—', '0', '2', 'Manage'],
          clients[:blank].id => ["Blank Studio ##{clients[:blank].id}", 'Active', 'No WhatsApp', '—', '0', '0', 'Manage'],
          clients[:nimbus].id => ["Nimbus Travels ##{clients[:nimbus].id}", 'Suspended', 'Official', '—', '0', '1', 'Manage']
        )
        manage = page.at_css("tr[data-account-id='#{account.id}'] a")
        expect(manage['href']).to eq("/super_admin/wadesk_clients/#{account.id}/edit")
        expect(manage['aria-label']).to eq('Manage Sharma Traders')
      end

      it 'filters by plan, with a count on each filter' do
        expected = {
          nil => clients.values_at(:both, :glow, :metro, :jewels, :blank, :nimbus),
          'both' => clients.values_at(:both),
          'web' => clients.values_at(:glow, :metro),
          'official' => clients.values_at(:jewels, :nimbus)
        }
        labels = { nil => 'All', 'both' => 'Both', 'web' => 'Web only', 'official' => 'Official only' }
        expected.each do |plan, accounts|
          get '/super_admin/wadesk_clients', params: { plan: plan }.compact

          expect(rows.keys).to eq(accounts.map(&:id)), "plan filter #{plan.inspect}"
          expect(filter_links.find { |_label, aria| aria == 'page' }.first).to start_with(labels[plan])
        end
        expect(filter_links.map(&:first)).to eq(['All 6', 'Both 1', 'Web only 2', 'Official only 2'])
      end

      it 'finds clients by name or id, keeping the plan filter' do
        get '/super_admin/wadesk_clients', params: { search: 'sharma' }
        expect(rows.keys).to eq([account.id])
        expect(filter_links.map(&:first)).to eq(['All 1', 'Both 1', 'Web only 0', 'Official only 0'])

        get '/super_admin/wadesk_clients', params: { search: clients[:metro].id.to_s }
        expect(rows.keys).to eq([clients[:metro].id])

        get '/super_admin/wadesk_clients', params: { search: 'r', plan: 'web' }
        expect(rows.keys).to eq([clients[:metro].id])
        expect(page.at_css('input[type=hidden][name=plan]')['value']).to eq('web')

        get '/super_admin/wadesk_clients', params: { search: 'nobody' }
        expect(page.at_css('tbody').text.squish).to eq('No client matches this search.')
      end

      it 'runs the same number of queries however many clients are listed' do
        count_queries = lambda do
          queries = 0
          counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
          ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get '/super_admin/wadesk_clients' }
          queries
        end
        get '/super_admin/wadesk_clients' # warm up per-process caches
        baseline = count_queries.call

        3.times do |index|
          extra = create(:account, name: "Extra #{index}")
          extra.enable_features!('whatsapp_web')
          whatsapp_web_number(extra, 'Desk', "+91990000000#{index}", { 'state' => 'logged_out', 'reason' => 'forbidden' })
          official_inbox(extra, 'whatsapp_cloud')
        end

        expect(count_queries.call).to eq(baseline)
        expect(rows.size).to eq(9)
      end
    end

    describe 'GET /super_admin/wadesk_clients/{account_id}/edit' do
      before do
        account.enable_features!('whatsapp_web', 'campaigns', 'macros', 'reports', 'agent_bots')
        official_inbox(account, 'whatsapp_cloud')
        create(:channel_twilio_sms, :whatsapp, account: account)
        whatsapp_web_number(account, 'Sales desk', '+919828074219', { 'state' => 'connected', 'me' => { 'phone' => '919828074219' } })
        whatsapp_web_number(account, 'Support', '+919829011420', { 'state' => 'logged_out', 'reason' => 'unlinked_from_phone' })
        whatsapp_web_number(account, 'Admissions', '+919414088213', { 'state' => 'qr_pending' })
        create(:user, account: account, role: :administrator)
        create(:user, account: account, role: :agent)
      end

      it 'shows the client with its status and plan cards' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        expect(response).to have_http_status(:success)
        header = page.at_css('header')
        expect([header.at_css('h1').text.squish, header.at_css('a')['href']]).to eq(['Sharma Traders', '/super_admin/wadesk_clients'])
        expect(header.text.squish).to include("##{account.id} · client since #{account.created_at.strftime('%-d %b %Y')}", 'Active')
        official = page.at_css('[data-switch="client_whatsapp_official"]')
        expect(official.at_css('input[type=checkbox][role=switch]')['checked']).to eq('checked')
        expect(official.text.squish).to include('WhatsApp Official', 'Meta Cloud API, 360dialog, Twilio · 2 existing',
                                                'Turning WhatsApp Official off keeps its 2 existing inboxes working')
        expect(page.at_css('[data-switch="client_whatsapp_web"]').text.squish).to include('Phone linked by QR code or pairing code · 3 existing')
      end

      it 'shows the client\'s WhatsApp Web numbers with their state, and its account facts' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        numbers = page.css('li[data-number-id]').map { |item| item.text.squish }
        expect(numbers).to eq(['Sales desk +919828074219 Connected',
                               'Support +919829011420 Removed from the phone\'s Linked devices Logged out',
                               'Admissions +919414088213 Waiting for scan'])
        expect(page.at_css('main a[href="/super_admin/whatsapp_web_numbers"]').text.squish).to eq('All numbers')
        facts = page.at_css('[data-account-facts]')
        expect(facts.css('dt, dd').map { |cell| cell.text.squish }).to eq(
          ['Status', 'Active', 'Official inboxes', '2', 'Agents', '2', 'Created', account.created_at.strftime('%-d %b %Y')]
        )
        # One console (CR-004): no links into Chatwoot's old admin panel.
        expect(page.css('main a[href^="/super_admin/accounts"]')).to be_empty
      end

      it 'says so when a client is suspended and has no WhatsApp Web numbers' do
        suspended = create(:account, name: 'Nimbus Travels', status: :suspended)

        get "/super_admin/wadesk_clients/#{suspended.id}/edit"

        expect(page.at_css('header').text).to include('Suspended')
        expect(page.text).to include('No WhatsApp Web numbers yet.')
        expect(page.at_css('[data-switch="client_whatsapp_web"] input[type=checkbox]')['checked']).to be_nil
        expect(page.at_css('[data-switch="client_whatsapp_official"] [data-off-warning]')).to be_nil # no inboxes to keep
      end

      it 'groups the allow-listed features, each switch reflecting the client\'s feature flag' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        groups = page.css('fieldset[data-feature-group]').map do |fieldset|
          [fieldset.at_css('legend').text.squish, fieldset.css('input[type=checkbox]').map { |box| box['name'][/\[features\]\[(\w+)\]/, 1] }]
        end
        expect(groups).to eq(Wadesk::ClientFeatures::GROUPS.map { |group| [group.title, group.features.map(&:name)] })
        expect(groups.to_h['Engagement']).to eq(%w[campaigns whatsapp_campaign help_center])
        switches = page.css('input[type=checkbox][name^="client[features]"]').to_h do |box|
          [box['name'][/\[features\]\[(\w+)\]/, 1], box['checked'] == 'checked']
        end
        expect(switches).to eq(Wadesk::ClientFeatures::NAMES.index_with { |name| account.feature_enabled?(name) })
        expect(switches.values_at('campaigns', 'macros', 'reports', 'whatsapp_campaign', 'data_import')).to eq([true, true, true, false, false])
        expect(page.at_css('[data-switch="client_features_campaigns"] label').text.squish).to eq('Campaigns')
      end

      it 'warns in plain words next to features that were on, for when they are turned off' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        warnings = %w[campaigns agent_bots whatsapp_campaign macros].index_with do |name|
          page.at_css("[data-switch='client_features_#{name}'] [data-off-warning]")&.text&.squish
        end
        expect(warnings).to eq('campaigns' => 'Website pop-up campaigns stop showing',
                               'agent_bots' => 'Bots already attached to inboxes keep replying',
                               'whatsapp_campaign' => nil, 'macros' => nil) # already off / nothing to warn about
        expect(page.text.squish).to include('Turned-off features are hidden from this client\'s app. ' \
                                            'Their data is kept, and turning a feature back on restores it.')
      end
    end

    describe 'PATCH /super_admin/wadesk_clients/{account_id}' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'turns a plan off while existing inboxes keep working, and the dashboard sees the change' do
        channel = official_inbox(account, 'whatsapp_cloud')

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_official: '0') }

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{account.id}/edit")
        expect(flash[:notice]).to eq('Plan for Sharma Traders updated. Existing WhatsApp Official inboxes keep working; only new ones are blocked.')
        get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
        expect(response.parsed_body['features']).to include('whatsapp_web' => true)
        expect(response.parsed_body['features']).not_to have_key('whatsapp_official')
        channel.reload.update!(provider_config: channel.provider_config.merge('api_key' => 'rotated_key'))
        expect(channel.reload.provider_config['api_key']).to eq('rotated_key')
      end

      it 'turns a plan back on and another off' do
        official_inbox(account, 'whatsapp_cloud')
        account.disable_features!('whatsapp_official')
        account.enable_features!('whatsapp_web')

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(whatsapp_web: '0') }

        expect(flash[:notice]).to eq('Plan for Sharma Traders updated.')
        expect(account.reload.feature_enabled?('whatsapp_official')).to be(true)
        expect(account.feature_enabled?('whatsapp_web')).to be(false)
      end

      it 'saves plan, limit and features in one submit, and the client dashboard sees the features' do
        account.enable_features!('campaigns', 'macros', 'reports')
        features = { campaigns: '0', macros: '0', reports: '1', data_import: '1', whatsapp_campaign: '1' }

        patch "/super_admin/wadesk_clients/#{account.id}",
              params: { client: plan_params.merge(whatsapp_official: '0', daily_new_chats: '30', features: features) }

        expect(flash[:notice]).to eq("Plan for Sharma Traders updated. Hidden from the client's app: Macros and Campaigns.")
        account.reload
        expect(%w[whatsapp_official whatsapp_web].index_with { |name| account.feature_enabled?(name) })
          .to eq('whatsapp_official' => false, 'whatsapp_web' => true)
        expect(account.custom_attributes[limit_key]).to eq(30)
        get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
        dashboard = response.parsed_body['features']
        expect(dashboard).to include('reports' => true, 'data_import' => true, 'whatsapp_campaign' => true)
        expect(dashboard.keys).not_to include('campaigns', 'macros')
      end

      it 'turns features back on, leaving features the form did not send as they were' do
        account.enable_features('data_import')
        account.disable_features!('campaigns', 'macros')

        patch "/super_admin/wadesk_clients/#{account.id}", params: { client: plan_params.merge(features: { campaigns: '1', macros: '1' }) }

        expect(flash[:notice]).to eq('Plan for Sharma Traders updated.')
        expect(%w[campaigns macros data_import].index_with { |name| account.reload.feature_enabled?(name) })
          .to eq('campaigns' => true, 'macros' => true, 'data_import' => true)
      end

      it 'ignores feature flags outside the allow-list, so they cannot be turned on or off here' do
        account.enable_features('inbound_emails')
        account.disable_features!('captain_integration', 'api_and_webhooks')

        patch "/super_admin/wadesk_clients/#{account.id}", params: {
          client: plan_params.merge(features: { captain_integration: '1', api_and_webhooks: '1', inbound_emails: '0', whatsapp_web: '0',
                                                campaigns: '1' })
        }

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{account.id}/edit")
        flags = %w[captain_integration api_and_webhooks inbound_emails whatsapp_web campaigns].index_with do |name|
          account.reload.feature_enabled?(name)
        end
        # whatsapp_web follows the plan switch, not features[...]; campaigns is allow-listed so it does change.
        expect(flags).to eq('captain_integration' => false, 'api_and_webhooks' => false, 'inbound_emails' => true, 'whatsapp_web' => true,
                            'campaigns' => true)
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
        it "rejects #{limit.inspect} as a limit, changes nothing and keeps the operator's choices" do
          account.update!(custom_attributes: account.custom_attributes.merge(limit_key => 40))
          account.enable_features!('campaigns')
          features = { campaigns: '0', data_import: '1' }

          patch "/super_admin/wadesk_clients/#{account.id}",
                params: { client: plan_params.merge(whatsapp_official: '0', daily_new_chats: limit, features: features) }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include('Daily new-chat limit must be a whole number from 1 to 1000, or blank for the default (20).')
          expect(account.reload.custom_attributes[limit_key]).to eq(40)
          expect(%w[whatsapp_official campaigns data_import].index_with { |name| account.feature_enabled?(name) })
            .to eq('whatsapp_official' => true, 'campaigns' => true, 'data_import' => false)
          # The form keeps what the operator chose, so a rejected limit does not undo their other changes.
          switches = %w[client[whatsapp_official] client[whatsapp_web] client[features][campaigns] client[features][data_import]]
          expect(switches.map { |name| page.at_css("input[type=checkbox][name='#{name}']")['checked'] }).to eq([nil, 'checked', nil, 'checked'])
          expect(page.at_css('[data-switch="client_features_campaigns"] [data-off-warning]').text.squish)
            .to eq('Website pop-up campaigns stop showing')
          expect([page.at_css('input[name="client[daily_new_chats]"]')['value'], page.at_css('[data-field-error]').present?]).to eq([limit, true])
        end
      end
    end
  end
end
