require 'rails_helper'

# WaDesk: the operator console creates, renames, suspends, reactivates and deletes clients, so the operator never needs
# Chatwoot's own admin pages. Expectations are scoped to the records each example makes (a local test DB may hold others).
RSpec.describe 'Super Admin WaDesk client lifecycle', type: :request do
  let(:super_admin) { create(:super_admin, name: 'Priya Operator') }
  let(:account) { create(:account, name: 'Sharma Traders') }
  let(:client_admin) { create(:user, account: account, role: :administrator, name: 'Ramesh Sharma') }
  let(:new_client) do
    { name: 'Kaveri Sweets', admin_name: 'Lakshmi Iyer', admin_email: 'lakshmi@kaverisweets.in', set_password: '0', admin_password: '' }
  end

  def page
    Nokogiri::HTML(response.body)
  end

  # The field's error text, found through the input's aria-describedby as a screen reader would.
  def field_error(input_id)
    input = page.at_css("##{input_id}")
    return unless input['aria-invalid'] == 'true'

    input['aria-describedby'].split.filter_map { |id| page.at_css("##{id}[data-field-error]")&.text&.squish }.first
  end

  describe 'access' do
    it 'refuses account users who are not super admins, and changes nothing' do
      sign_in(client_admin, scope: :user)

      get '/super_admin/wadesk_clients/new'
      expect(response).to redirect_to('/super_admin/sign_in')

      expect { post '/super_admin/wadesk_clients', params: { client: new_client } }.not_to change(Account, :count)
      expect(response).to redirect_to('/super_admin/sign_in')

      patch "/super_admin/wadesk_clients/#{account.id}/rename", params: { client: { name: 'Hacked' } }
      post "/super_admin/wadesk_clients/#{account.id}/suspend", params: { suspension: { category: 'spam', reason: 'x' } }
      expect(account.reload).to have_attributes(name: 'Sharma Traders', status: 'active')

      account.update!(status: :suspended)
      post "/super_admin/wadesk_clients/#{account.id}/reactivate"
      expect(account.reload.status).to eq('suspended')

      delete "/super_admin/wadesk_clients/#{account.id}", params: { confirm_name: 'Sharma Traders' }
      expect(response).to redirect_to('/super_admin/sign_in')
      expect(DeleteObjectJob).not_to have_been_enqueued
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'new client' do
      let(:created) { Account.find_by!(name: 'Kaveri Sweets') }

      it 'is reached from the Clients list and shows an accessible form' do
        get '/super_admin/wadesk_clients'
        expect(page.at_css('header a[data-new-client]')['href']).to eq('/super_admin/wadesk_clients/new')

        get '/super_admin/wadesk_clients/new'

        expect(response).to have_http_status(:success)
        labels = page.css('form label[for]').to_h { |label| [label['for'], label.text.squish] }
        expect(labels).to eq('client_name' => 'Client name', 'client_admin_name' => 'Admin name', 'client_admin_email' => 'Admin email',
                             'client_set_password' => 'Set a password now', 'client_admin_password' => 'Password')
        expect(page.at_css('#client_admin_password')['aria-describedby']).to eq('client_admin_password-hint')
        expect(page.at_css('#client_admin_password-hint').text).to include('At least 6 characters')
      end

      it 'creates the client with default features and emails the new administrator an invitation to set a password' do
        expect { post '/super_admin/wadesk_clients', params: { client: new_client } }.to change(Account, :count).by(1)

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{created.id}/edit")
        expect(flash[:notice]).to eq('Kaveri Sweets created. An invitation to set a password was emailed to lakshmi@kaverisweets.in.')
        admin = User.from_email('lakshmi@kaverisweets.in')
        expect(admin).to have_attributes(name: 'Lakshmi Iyer', confirmed?: false)
        expect(created.account_users.map { |member| [member.user_id, member.role, member.inviter_id] })
          .to eq([[admin.id, 'administrator', super_admin.id]])
        defaults = YAML.safe_load(Rails.root.join('config/features.yml').read).select { |feature| feature['enabled'] }.pluck('name')
        expect(defaults.select { |feature| created.feature_enabled?(feature) }).to eq(defaults)

        perform_enqueued_jobs
        mail = ActionMailer::Base.deliveries.find { |delivery| delivery.to == ['lakshmi@kaverisweets.in'] }
        body = mail.html_part&.decoded || mail.body.decoded
        expect(body).to include('Priya Operator invited you to join the Kaveri Sweets workspace', 'auth/password/edit?reset_password_token=')
      end

      it 'sets a password now instead: no email, and the administrator can sign in with it' do
        params = new_client.merge(set_password: '1', admin_password: 'Kaveri@2026')

        post '/super_admin/wadesk_clients', params: { client: params }

        expect(ActionMailer::MailDeliveryJob).not_to have_been_enqueued
        expect(flash[:notice]).to eq('Kaveri Sweets created. Lakshmi Iyer can sign in now as lakshmi@kaverisweets.in with the password you set.')
        admin = User.from_email('lakshmi@kaverisweets.in')
        expect(admin.confirmed?).to be(true)
        expect(admin.account_users.map { |member| [member.account_id, member.role] }).to eq([[created.id, 'administrator']])

        post '/auth/sign_in', params: { email: 'lakshmi@kaverisweets.in', password: 'Kaveri@2026' }, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body.dig('data', 'accounts').pluck('id', 'role')).to eq([[created.id, 'administrator']])
      end

      it 'adds a user who already has a login as the administrator, keeping their name and password, without emailing' do
        client_admin.update!(password: 'Sharma@2026', password_confirmation: 'Sharma@2026')
        params = new_client.merge(name: 'Sharma Exports', admin_name: 'Someone Else', admin_email: " #{client_admin.email.upcase} ",
                                  set_password: '1', admin_password: 'Other@2026')

        expect { post '/super_admin/wadesk_clients', params: { client: params } }.not_to change(User, :count)

        exports = Account.find_by!(name: 'Sharma Exports')
        expect(response).to redirect_to("/super_admin/wadesk_clients/#{exports.id}/edit")
        expect(flash[:notice]).to eq("Sharma Exports created. #{client_admin.email} already had a WaDesk login, so that user was added " \
                                     'as the client\'s administrator. No invitation was sent and their password is unchanged.')
        expect(client_admin.reload.account_users.map { |member| [member.account_id, member.role] })
          .to contain_exactly([account.id, 'administrator'], [exports.id, 'administrator'])
        expect([client_admin.name, client_admin.valid_password?('Sharma@2026')]).to eq(['Ramesh Sharma', true])
        expect(ActionMailer::MailDeliveryJob).not_to have_been_enqueued
      end

      it 'lands on the new client page, showing the notice' do
        post '/super_admin/wadesk_clients', params: { client: new_client }
        follow_redirect!

        expect(page.at_css('h1').text.squish).to eq('Kaveri Sweets')
        expect(page.at_css('[role=status]').text.squish).to start_with('Kaveri Sweets created.')
      end

      {
        'a blank client name' => [{ name: '  ' }, 'client_name', 'Client name can\'t be blank'],
        'a malformed email' => [{ admin_email: 'lakshmi@' }, 'client_admin_email', 'Admin email is invalid'],
        'an email without a real domain' => [{ admin_email: 'lakshmi@kaverisweets' }, 'client_admin_email', 'Admin email is not an email'],
        'a blank admin name' => [{ admin_name: '' }, 'client_admin_name', 'Admin name can\'t be blank'],
        'a short password' => [{ set_password: '1', admin_password: 'K@1a' }, 'client_admin_password',
                               'Password must contain at least 6 characters'],
        'a password without a special character' => [{ set_password: '1', admin_password: 'Kaveri2026' }, 'client_admin_password',
                                                     "Password must contain at least 1 special character ( !@\#$%^&*()_+-=[]{}|\"/\\.,`<>:;?~')"]
      }.each do |problem, (changes, field, message)|
        it "rejects #{problem}, creating nothing and keeping what was typed" do
          params = new_client.merge(changes)

          expect { post '/super_admin/wadesk_clients', params: { client: params } }.not_to change(Account, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.from_email(params[:admin_email])).to be_nil
          expect(field_error(field)).to eq(message)
          expect(page.css('[data-error-summary] li').map { |item| item.text.squish }).to include(message)
          expect(page.css('#client_name, #client_admin_name, #client_admin_email').map { |input| input['value'].to_s })
            .to eq(params.values_at(:name, :admin_name, :admin_email))
          expect(page.at_css('#client_set_password')['checked']).to eq(params[:set_password] == '1' ? 'checked' : nil)
        end
      end
    end

    describe 'rename' do
      it 'renames the client and shows the created date on its page' do
        patch "/super_admin/wadesk_clients/#{account.id}/rename", params: { client: { name: ' Sharma Traders Pvt Ltd ' } }

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{account.id}/edit")
        expect(flash[:notice]).to eq('Renamed Sharma Traders to Sharma Traders Pvt Ltd.')
        expect(account.reload.name).to eq('Sharma Traders Pvt Ltd')
        follow_redirect!
        expect(page.at_css('h1').text.squish).to eq('Sharma Traders Pvt Ltd')
        expect(page.at_css('#rename_name')['value']).to eq('Sharma Traders Pvt Ltd')
        facts = page.at_css('[data-account-facts]').css('dt, dd').map { |cell| cell.text.squish }.each_slice(2).to_h
        expect(facts['Created']).to eq(account.created_at.strftime('%-d %b %Y'))
      end

      it 'refuses a blank name, with the error next to the field' do
        patch "/super_admin/wadesk_clients/#{account.id}/rename", params: { client: { name: '   ' } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.name).to eq('Sharma Traders')
        expect(field_error('rename_name')).to eq('Enter the client\'s name.')
        expect(page.at_css('h1').text.squish).to eq('Sharma Traders')
      end
    end

    describe 'suspend and reactivate' do
      let(:suspend_params) { { suspension: { category: 'non_payment', reason: ' Invoice for August not paid after two reminders ' } } }

      it 'explains what suspension does before the operator suspends' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        form = page.at_css('form[data-suspend-form]')
        expect(form['action']).to eq("/super_admin/wadesk_clients/#{account.id}/suspend")
        expect(form.css('#suspension_category option').map { |option| option.text.squish })
          .to eq(['Choose a category', 'Spam', 'Non-payment', 'Other'])
        expect(form.at_css('[data-suspend-warning]').text.squish).to include(
          'can still sign in, but sees only an "Account suspended" page',
          'New incoming WhatsApp messages and emails are dropped and not saved'
        )
      end

      it 'suspends with a reason: the client\'s app refuses it and the client page shows why' do
        client_admin

        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{account.id}/edit")
        expect(flash[:notice]).to start_with('Sharma Traders is suspended.')
        account.reload
        expect([account.suspended?, account.active?]).to eq([true, false])
        expect(account.suspension_history.last).to include('category' => 'non_payment', 'reason' => 'Invoice for August not paid after two reminders',
                                                           'suspended_by' => super_admin.id)

        get "/api/v1/accounts/#{account.id}/inboxes", headers: client_admin.create_new_auth_token, as: :json
        expect([response.status, response.parsed_body['error']]).to eq([401, 'Account is suspended'])
      end

      it 'shows the suspension on the client page: status pill, category, date, operator and reason' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params
        follow_redirect!

        expect(page.at_css('header').text.squish).to include('Suspended')
        banner = page.at_css('[data-suspended-banner]').text.squish
        expect(banner).to include("Non-payment · since #{Time.zone.today.strftime('%-d %b %Y')} · by Priya Operator",
                                  'Reason: Invoice for August not paid after two reminders')
        expect(page.at_css('form[data-suspend-form]')).to be_nil
      end

      it 'shows a suspended client as Suspended on the Clients list' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params

        get '/super_admin/wadesk_clients', params: { search: 'Sharma Traders' }
        expect(page.at_css("tr[data-account-id='#{account.id}'] td[data-column=status]").text.squish).to eq('Suspended')
      end

      it 'records the suspension where Chatwoot\'s own admin shows its history' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params

        get "/super_admin/accounts/#{account.id}"
        expect(page.text.squish).to include('Non-payment', 'Invoice for August not paid after two reminders', 'Priya Operator')
      end

      {
        'no category' => [{ category: '', reason: 'Spam complaints' }, 'suspension_category', 'Category can\'t be blank'],
        'an unknown category' => [{ category: 'fraud', reason: 'Spam complaints' }, 'suspension_category', 'Category is not included in the list'],
        'a blank reason' => [{ category: 'spam', reason: '  ' }, 'suspension_reason', 'Reason can\'t be blank'],
        'a reason over 256 characters' => [{ category: 'other', reason: 'a' * 257 }, 'suspension_reason',
                                           'Reason is too long (maximum is 256 characters)']
      }.each do |problem, (suspension, field, message)|
        it "refuses #{problem}, leaving the client active and keeping the input" do
          post "/super_admin/wadesk_clients/#{account.id}/suspend", params: { suspension: suspension }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(account.reload).to have_attributes(status: 'active', suspension_history: [])
          expect(field_error(field)).to eq(message)
          selected = page.at_css('#suspension_category option[selected]')&.[]('value').to_s
          expect(selected).to eq(Account::SUSPENSION_CATEGORIES.include?(suspension[:category]) ? suspension[:category] : '')
          expect(page.at_css('#suspension_reason').text.strip).to eq(suspension[:reason].strip)
        end
      end

      it 'does not add another suspension to a client that is already suspended' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: { suspension: { category: 'spam', reason: 'Again' } }

        expect(flash[:alert]).to eq('Sharma Traders is already suspended.')
        expect(account.reload.suspension_history.pluck('category')).to eq(['non_payment'])
      end

      it 'reactivates: the client\'s app works again and the suspension stays in the history' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params
        post "/super_admin/wadesk_clients/#{account.id}/reactivate"

        expect(response).to redirect_to("/super_admin/wadesk_clients/#{account.id}/edit")
        expect(flash[:notice]).to eq('Sharma Traders is active again. Its team can use WaDesk and new incoming messages are saved again.')
        expect(account.reload.active?).to be(true)
        expect(account.suspension_history.size).to eq(1)
        get "/api/v1/accounts/#{account.id}/inboxes", headers: client_admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'offers Reactivate on a suspended client\'s page, and the page shows it active again afterwards' do
        post "/super_admin/wadesk_clients/#{account.id}/suspend", params: suspend_params
        get "/super_admin/wadesk_clients/#{account.id}/edit"
        expect(page.at_css('[data-suspended-banner] form')['action']).to eq("/super_admin/wadesk_clients/#{account.id}/reactivate")

        post "/super_admin/wadesk_clients/#{account.id}/reactivate"
        follow_redirect!

        expect(page.at_css('[data-suspended-banner]')).to be_nil
        expect(page.at_css('header').text.squish).to include('Active')
        expect(page.at_css('form[data-suspend-form]')).to be_present
      end
    end

    describe 'delete' do
      it 'explains what is deleted in a danger zone that asks for the client\'s name' do
        get "/super_admin/wadesk_clients/#{account.id}/edit"

        zone = page.at_css('[data-danger-zone]')
        expect(zone.text.squish).to include('Permanently deletes the client\'s conversations, messages, contacts, inboxes', 'cannot be undone')
        expect(zone.at_css('label[for=confirm_name]').text.squish).to eq('Type Sharma Traders to confirm')
        expect(zone.at_css('form input[name=_method]')['value']).to eq('delete')
      end

      ['Sharma', 'sharma traders', ''].each do |typed|
        it "does nothing when #{typed.inspect} is typed instead of the exact name" do
          delete "/super_admin/wadesk_clients/#{account.id}", params: { confirm_name: typed }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(DeleteObjectJob).not_to have_been_enqueued
          expect(Account.exists?(account.id)).to be(true)
          expect(field_error('confirm_name')).to eq('Type Sharma Traders exactly to delete this client.')
          expect(page.at_css('#confirm_name')['value'].to_s).to eq(typed)
        end
      end

      it 'enqueues Chatwoot\'s account deletion when the exact name is typed, and the client is then gone' do
        client_admin

        delete "/super_admin/wadesk_clients/#{account.id}", params: { confirm_name: 'Sharma Traders' }

        expect(response).to redirect_to('/super_admin/wadesk_clients')
        expect(flash[:notice]).to eq('Deleting Sharma Traders. This runs in the background and can take a few minutes.')
        expect(DeleteObjectJob).to have_been_enqueued.with(account)

        perform_enqueued_jobs(only: DeleteObjectJob)
        expect(Account.exists?(account.id)).to be(false)
        expect(User.exists?(client_admin.id)).to be(true)
      end
    end
  end
end
