require 'rails_helper'

# WaDesk: the operator console's Users pages: list, user page, client memberships, invitation, password and operator access.
RSpec.describe 'Super Admin WaDesk users', type: :request do
  let(:domain) { 'wadesk-users.test' }
  let!(:sharma) { create(:account, name: 'Sharma Traders') }
  let!(:glow) { create(:account, name: 'Glow Dental Clinic') }
  let!(:metro) { create(:account, name: 'Metro Realty') }
  let!(:super_admin) { create(:super_admin, name: 'Vikram Mehta', email: "vikram.mehta@#{domain}") }
  let!(:second_operator) { create(:super_admin, name: 'Neha Kapoor', email: "neha.kapoor@#{domain}") }
  let!(:priya) do
    create(:user, name: 'Priya Sharma', email: "priya.sharma@#{domain}", account: sharma, role: :administrator).tap do |user|
      create(:account_user, user: user, account: glow, role: :administrator)
      create(:account_user, user: user, account: metro, role: :agent)
      user.update!(last_sign_in_at: 3.hours.ago)
    end
  end
  let!(:rahul) { create(:user, name: 'Rahul Verma', email: "rahul.verma@#{domain}", account: sharma, role: :agent) }
  let!(:anjali) { create(:user, name: 'Anjali Iyer', email: "anjali.iyer@#{domain}", account: glow, role: :agent, skip_confirmation: false) }

  def page
    Nokogiri::HTML(response.body)
  end

  def row(user)
    page.at_css("tr[data-user-id='#{user.id}']")
  end

  def listed_ids
    page.css('tbody tr[data-user-id]').map { |tr| tr['data-user-id'].to_i }
  end

  def flash_text
    page.at_css('[role=status]')&.text&.squish
  end

  describe 'access' do
    it 'sends signed-out visitors to the login page' do
      get '/super_admin/wadesk_users'

      expect(response).to redirect_to('/super_admin/sign_in')
    end

    it 'refuses account users who are not super admins, for every action' do
      sign_in(priya, scope: :user)
      membership = rahul.account_users.first
      new_password = { user: { password: 'Hacked123!', password_confirmation: 'Hacked123!' } }
      requests = [
        -> { get '/super_admin/wadesk_users' },
        -> { get "/super_admin/wadesk_users/#{rahul.id}" },
        -> { get '/super_admin/wadesk_users/new' },
        -> { post '/super_admin/wadesk_users', params: { user: { name: 'X', email: "x@#{domain}", account_id: sharma.id, role: 'agent' } } },
        -> { post "/super_admin/wadesk_users/#{rahul.id}/memberships", params: { membership: { account_id: glow.id, role: 'administrator' } } },
        -> { delete "/super_admin/wadesk_users/#{rahul.id}/memberships/#{membership.id}" },
        -> { post "/super_admin/wadesk_users/#{anjali.id}/resend_confirmation" },
        -> { post "/super_admin/wadesk_users/#{anjali.id}/confirm" },
        -> { patch "/super_admin/wadesk_users/#{rahul.id}/password", params: new_password },
        -> { patch "/super_admin/wadesk_users/#{priya.id}/operator", params: { operator: '1' } }
      ]

      requests.each do |request|
        request.call
        expect(response).to redirect_to('/super_admin/sign_in')
      end
      expect(User.exists?(email: "x@#{domain}")).to be(false)
      expect(rahul.account_users.pluck(:account_id)).to eq([sharma.id])
      expect(anjali.reload.confirmed?).to be(false)
      expect(rahul.reload.valid_password?('Hacked123!')).to be(false)
      expect(priya.reload.type).to be_nil
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'GET /super_admin/wadesk_users' do
      it 'lists users by name, each row opening the user page and showing their clients with role' do
        get '/super_admin/wadesk_users', params: { search: domain }

        expect(response).to have_http_status(:ok)
        expect(listed_ids).to eq([anjali, second_operator, priya, rahul, super_admin].map(&:id))
        link = row(priya).at_css('[data-column=user] a')
        expect(link['href']).to eq("/super_admin/wadesk_users/#{priya.id}")
        expect(link['class']).to include('after:absolute')
        expect(row(priya).at_css('[data-column=user]').text.squish).to eq("Priya Sharma priya.sharma@#{domain}")
        expect(row(priya).at_css('[data-column=clients]').text.squish).to eq('Glow Dental Clinic · Admin Metro Realty · Agent +1 more')
        expect(row(rahul).at_css('[data-column=clients]').text.squish).to eq('Sharma Traders · Agent')
      end

      it 'shows the invitation state, the last sign-in and an Operator pill for super admins' do
        get '/super_admin/wadesk_users', params: { search: domain }

        expect(row(priya).css('[data-column=status], [data-column=last-sign-in]').map { |cell| cell.text.squish })
          .to eq(['Confirmed', 'about 3 hours ago'])
        expect(row(anjali).css('[data-column=status], [data-column=last-sign-in]').map { |cell| cell.text.squish })
          .to eq(['Invite pending', 'Never'])
        expect(row(super_admin).at_css('[data-column=user]').text.squish).to eq("Vikram Mehta Operator vikram.mehta@#{domain}")
        expect(row(super_admin).at_css('[data-column=clients]').text.squish).to eq('No client')
        expect(row(rahul).at_css('[data-column=user]').text.squish).to eq("Rahul Verma rahul.verma@#{domain}")
      end

      it 'searches by name or email, case-insensitively' do
        get '/super_admin/wadesk_users', params: { search: 'priya' }
        expect(listed_ids & [priya, rahul, anjali].map(&:id)).to eq([priya.id])

        get '/super_admin/wadesk_users', params: { search: "RAHUL.VERMA@#{domain}" }
        expect(listed_ids).to eq([rahul.id])

        get '/super_admin/wadesk_users', params: { search: 'nobody-by-this-name' }
        expect(page.at_css('[data-empty=users]').text.squish).to eq('No user matches “nobody-by-this-name”.')
      end

      it 'filters operators and unconfirmed invites, with counts, keeping the search' do
        get '/super_admin/wadesk_users', params: { search: domain, filter: 'operators' }
        expect(listed_ids).to contain_exactly(super_admin.id, second_operator.id)
        counts = page.css('nav[aria-label="Filter users"] a').to_h { |link| [link['data-filter'], link.text.squish] }
        expect(counts).to eq('all' => 'All 5', 'operators' => 'Operators 2', 'unconfirmed' => 'Unconfirmed 1')
        expect(page.at_css('a[data-filter=operators]')['aria-current']).to eq('page')
        expect(page.at_css('input[type=hidden][name=filter]')['value']).to eq('operators')

        get '/super_admin/wadesk_users', params: { search: domain, filter: 'unconfirmed' }
        expect(listed_ids).to eq([anjali.id])

        get '/super_admin/wadesk_users', params: { search: domain, filter: 'bogus' }
        expect(listed_ids.size).to eq(5)
      end

      it 'pages through 25 users at a time' do
        24.times { |index| create(:user, name: "Kiran Rao #{index.to_s.rjust(2, '0')}", email: "kiran#{index}@#{domain}", account: metro) }

        get '/super_admin/wadesk_users', params: { search: domain }
        expect(listed_ids.size).to eq(25)
        expect(page.at_css('nav[aria-label=Pages]').text.squish).to eq('1–25 of 29 Next')

        get page.at_css('a[rel=next]')['href']
        expect(listed_ids.size).to eq(4)
        expect(page.at_css('a[rel=prev]')).to be_present
      end

      it 'runs the same number of queries however many users and memberships are listed' do
        count_queries = lambda do
          queries = 0
          counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
          ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get '/super_admin/wadesk_users', params: { search: domain } }
          queries
        end
        get '/super_admin/wadesk_users', params: { search: domain } # warm up per-process caches
        baseline = count_queries.call

        3.times do |index|
          user = create(:user, name: "Deepak Nair #{index}", email: "deepak#{index}@#{domain}", account: sharma, role: :administrator)
          create(:account_user, user: user, account: glow)
          create(:account_user, user: user, account: metro)
        end

        expect(count_queries.call).to eq(baseline)
        expect(listed_ids.size).to eq(8)
      end
    end

    describe 'GET /super_admin/wadesk_users/{id}' do
      it 'shows details and the clients with role and a link to each client page' do
        get "/super_admin/wadesk_users/#{priya.id}"

        expect(response).to have_http_status(:ok)
        expect(page.at_css('h1').text.squish).to eq('Priya Sharma')
        memberships = page.css('[data-membership-id]')
        expect(memberships.map { |li| li.at_css('a').text }).to eq(['Glow Dental Clinic', 'Metro Realty', 'Sharma Traders'])
        expect(memberships.first.at_css('a')['href']).to eq("/super_admin/wadesk_clients/#{glow.id}/edit")
        expect(memberships.first.text.squish).to include('· Admin')
        expect(page.css('#membership_account_id option').map(&:text)).not_to include('Glow Dental Clinic', 'Metro Realty', 'Sharma Traders')
        expect(page.at_css('[data-user-details]').text.squish).to include("Email priya.sharma@#{domain}", 'Last sign-in about 3 hours ago')
      end

      it 'offers only the clients the user is not in yet' do
        get "/super_admin/wadesk_users/#{rahul.id}"

        options = page.css('#membership_account_id option').map(&:text)
        expect(options).to include('Glow Dental Clinic', 'Metro Realty')
        expect(options).not_to include('Sharma Traders')
      end

      it 'offers the invitation actions only to an unconfirmed user' do
        get "/super_admin/wadesk_users/#{anjali.id}"

        actions = page.at_css('[data-invitation-actions]')
        expect(actions.css('button').map(&:text)).to eq(['Resend invitation', 'Mark email as confirmed'])

        get "/super_admin/wadesk_users/#{priya.id}"
        expect(page.at_css('[data-invitation-actions]')).to be_nil
      end

      it 'explains why the last administrator of a client cannot be removed' do
        get "/super_admin/wadesk_users/#{priya.id}"

        glow_item = page.at_css("[data-membership-id='#{priya.account_users.find_by(account: glow).id}']")
        expect(glow_item.at_css('[data-last-admin]').text.squish).to include('Only administrator of Glow Dental Clinic')
        expect(glow_item.at_css('form')).to be_nil
        metro_item = page.at_css("[data-membership-id='#{priya.account_users.find_by(account: metro).id}']")
        expect(metro_item.at_css('details form button').text).to eq('Yes, remove')
      end
    end

    describe 'client memberships' do
      it 'adds the user to a client with the chosen role; they then see that account' do
        expect do
          post "/super_admin/wadesk_users/#{rahul.id}/memberships", params: { membership: { account_id: glow.id, role: 'administrator' } }
        end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

        expect(response).to redirect_to("/super_admin/wadesk_users/#{rahul.id}")
        follow_redirect!
        expect(flash_text).to eq('Rahul Verma was added to Glow Dental Clinic as Admin.')
        membership = rahul.account_users.find_by(account: glow)
        expect(membership.role).to eq('administrator')
        expect(membership.inviter_id).to eq(super_admin.id)
        expect(rahul.reload.accounts).to include(glow)
      end

      it 'refuses an unknown role, and a client the user is already in' do
        post "/super_admin/wadesk_users/#{rahul.id}/memberships", params: { membership: { account_id: glow.id, role: 'owner' } }
        follow_redirect!
        expect(flash_text).to eq('Choose Administrator or Agent.')

        post "/super_admin/wadesk_users/#{rahul.id}/memberships", params: { membership: { account_id: sharma.id, role: 'agent' } }
        follow_redirect!
        expect(flash_text).to eq('Rahul Verma already belongs to Sharma Traders.')
        expect(rahul.account_users.count).to eq(1)
      end

      it 'removes the user from a client; they lose that account' do
        membership = priya.account_users.find_by(account: metro)

        delete "/super_admin/wadesk_users/#{priya.id}/memberships/#{membership.id}"

        follow_redirect!
        expect(flash_text).to eq('Priya Sharma was removed from Metro Realty.')
        expect(AccountUser.exists?(membership.id)).to be(false)
        expect(priya.reload.accounts).not_to include(metro)
      end

      it 'refuses to remove the last administrator of a client and says why' do
        membership = priya.account_users.find_by(account: glow)

        delete "/super_admin/wadesk_users/#{priya.id}/memberships/#{membership.id}"

        follow_redirect!
        expect(flash_text).to include('Priya Sharma is the only administrator of Glow Dental Clinic', 'add another administrator first')
        expect(AccountUser.exists?(membership.id)).to be(true)
      end

      it 'removes an administrator when the client has another one' do
        create(:user, name: 'Sunita Rao', email: "sunita.rao@#{domain}", account: glow, role: :administrator)
        membership = priya.account_users.find_by(account: glow)

        delete "/super_admin/wadesk_users/#{priya.id}/memberships/#{membership.id}"

        expect(AccountUser.exists?(membership.id)).to be(false)
      end
    end

    describe 'POST /super_admin/wadesk_users/{id}/resend_confirmation' do
      it 'sends the invitation again to an unconfirmed user' do
        expect do
          post "/super_admin/wadesk_users/#{anjali.id}/resend_confirmation"
        end.to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

        follow_redirect!
        expect(flash_text).to eq("Invitation sent again to anjali.iyer@#{domain}.")
      end

      it 'sends nothing to a user who already accepted' do
        expect do
          post "/super_admin/wadesk_users/#{rahul.id}/resend_confirmation"
        end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

        follow_redirect!
        expect(flash_text).to eq('Rahul Verma has already accepted the invitation.')
      end
    end

    describe 'POST /super_admin/wadesk_users/{id}/confirm' do
      it 'confirms the email so the user can log in' do
        post "/super_admin/wadesk_users/#{anjali.id}/confirm"

        follow_redirect!
        expect(flash_text).to include("anjali.iyer@#{domain} is confirmed")
        expect(anjali.reload.confirmed?).to be(true)
        post '/auth/sign_in', params: { email: anjali.email, password: 'Password1!' }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'PATCH /super_admin/wadesk_users/{id}/password' do
      it 'sets a new password the user can log in with' do
        patch "/super_admin/wadesk_users/#{rahul.id}/password", params: { user: { password: 'Rahul@2026', password_confirmation: 'Rahul@2026' } }

        follow_redirect!
        expect(flash_text).to eq('New password saved. Rahul Verma can log in with it now.')
        post '/auth/sign_in', params: { email: rahul.email, password: 'Rahul@2026' }, as: :json
        expect(response).to have_http_status(:ok)
        post '/auth/sign_in', params: { email: rahul.email, password: 'Password1!' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'refuses a confirmation that does not match' do
        patch "/super_admin/wadesk_users/#{rahul.id}/password", params: { user: { password: 'Rahul@2026', password_confirmation: 'Rahul@2027' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#password-errors').text.squish).to eq("Password confirmation doesn't match Password")
        expect(rahul.reload.valid_password?('Password1!')).to be(true)
      end

      it 'refuses a password that breaks Chatwoot\'s rules' do
        patch "/super_admin/wadesk_users/#{rahul.id}/password", params: { user: { password: 'Ab1!', password_confirmation: 'Ab1!' } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#password-errors').text).to include('Password must contain at least 6 characters')

        patch "/super_admin/wadesk_users/#{rahul.id}/password", params: { user: { password: 'rahulverma', password_confirmation: 'rahulverma' } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(page.css('#password-errors li').map { |item| item.text[/\APassword must contain at least 1 (\w+)/, 1] })
          .to eq(%w[uppercase number special])

        patch "/super_admin/wadesk_users/#{rahul.id}/password", params: { user: { password: '', password_confirmation: '' } }
        expect(page.css('#password-errors li').map(&:text).first).to eq('Password must contain at least 6 characters')
        expect(rahul.reload.valid_password?('Password1!')).to be(true)
      end
    end

    describe 'PATCH /super_admin/wadesk_users/{id}/operator' do
      it 'makes a user an operator, who can then open the console' do
        patch "/super_admin/wadesk_users/#{priya.id}/operator", params: { operator: '1' }

        follow_redirect!
        expect(flash_text).to eq('Priya Sharma is now an operator and can open this console.')
        expect(priya.reload.type).to eq('SuperAdmin')

        sign_out(:super_admin)
        post '/super_admin/sign_in', params: { super_admin: { email: priya.email, password: 'Password1!' } }
        expect(response).to redirect_to('/super_admin')
        get '/super_admin/wadesk_users'
        expect(response).to have_http_status(:ok)
      end

      it 'removes another operator\'s access; they can no longer open the console' do
        patch "/super_admin/wadesk_users/#{second_operator.id}/operator", params: { operator: '0' }

        follow_redirect!
        expect(flash_text).to eq('Neha Kapoor is no longer an operator.')
        expect(User.find(second_operator.id).type).to be_nil

        sign_out(:super_admin)
        post '/super_admin/sign_in', params: { super_admin: { email: second_operator.email, password: 'Password1!' } }
        expect(response).to redirect_to('/super_admin/sign_in')
        get '/super_admin/wadesk_users'
        expect(response).to redirect_to('/super_admin/sign_in')
      end

      it 'refuses to remove your own operator access' do
        patch "/super_admin/wadesk_users/#{super_admin.id}/operator", params: { operator: '0' }

        follow_redirect!
        expect(flash_text).to eq('You can\'t remove your own operator access. Ask another operator to do it.')
        expect(User.find(super_admin.id).type).to eq('SuperAdmin')
      end

      it 'refuses to remove the last operator' do
        SuperAdmin.where.not(id: second_operator.id).update_all(type: nil) # rubocop:disable Rails/SkipsModelValidations
        sign_in(second_operator, scope: :super_admin)

        patch "/super_admin/wadesk_users/#{second_operator.id}/operator", params: { operator: '0' }

        follow_redirect!
        expect(flash_text).to eq('There must always be at least one operator. Make someone else an operator first.')
        expect(User.find(second_operator.id).type).to eq('SuperAdmin')
      end

      it 'explains what an operator can do and hides removal on your own page' do
        get "/super_admin/wadesk_users/#{super_admin.id}"
        expect(page.at_css('#operator-title').parent.text.squish).to include('Operators run this console')
        expect(page.at_css('[data-operator-access]').text.squish).to include('This is you.')
        expect(page.at_css('[data-operator-access] form')).to be_nil

        get "/super_admin/wadesk_users/#{second_operator.id}"
        expect(page.at_css('[data-operator-access] form button').text).to eq('Yes, remove operator access')
      end
    end

    describe 'new user' do
      it 'invites a new user to a client with the chosen role' do
        get '/super_admin/wadesk_users/new'
        expect(page.css('#user_account_id option').map(&:text)).to include('Sharma Traders', 'Glow Dental Clinic')

        expect do
          post '/super_admin/wadesk_users',
               params: { user: { name: 'Arjun Patel', email: "Arjun.Patel@#{domain}", account_id: metro.id, role: 'administrator' } }
        end.to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

        arjun = User.find_by!(email: "arjun.patel@#{domain}")
        expect(response).to redirect_to("/super_admin/wadesk_users/#{arjun.id}")
        expect(arjun.name).to eq('Arjun Patel')
        expect(arjun.confirmed?).to be(false)
        expect(arjun.account_users.pluck(:account_id, :role)).to eq([[metro.id, 'administrator']])
      end

      it 'does not create a second user with an existing email, and links to them' do
        expect do
          post '/super_admin/wadesk_users', params: { user: { name: 'Rahul', email: rahul.email, account_id: glow.id, role: 'agent' } }
        end.not_to change(AccountUser, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#new-user-error a')['href']).to eq("/super_admin/wadesk_users/#{rahul.id}")
      end

      it 'requires a client and a valid email' do
        post '/super_admin/wadesk_users', params: { user: { name: 'Meera', email: "meera@#{domain}", account_id: '', role: 'agent' } }
        expect(page.at_css('#new-user-error').text.squish).to eq('Choose the client this user belongs to.')

        post '/super_admin/wadesk_users', params: { user: { name: 'Meera', email: 'not-an-email', account_id: sharma.id, role: 'agent' } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css('#new-user-error').text).to include('Email')
        expect(User.exists?(email: 'not-an-email')).to be(false)
      end
    end
  end
end
