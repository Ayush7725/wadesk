require 'rails_helper'

# WaDesk: emails name the installation's brand (BRAND_NAME), never Chatwoot.
RSpec.describe AdministratorNotifications::BaseMailer do
  let(:account) { create(:account, name: 'Sharma Traders', custom_attributes: { 'marked_for_deletion_at' => 7.days.from_now.iso8601 }) }
  let(:body) { mail.html_part ? mail.html_part.body.decoded : mail.body.decoded }

  around do |example|
    GlobalConfig.clear_cache
    example.run
    GlobalConfig.clear_cache
  end

  before do
    InstallationConfig.find_or_initialize_by(name: 'BRAND_NAME').update!(value: 'Acme Desk')
    InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: '')
    InstallationConfig.find_or_initialize_by(name: 'CHATWOOT_INSTANCE_ADMIN_EMAIL').update!(value: 'operator@acme.example')
    create(:user, account: account, role: :administrator)
    Current.account = account
    allow_any_instance_of(described_class).to receive(:smtp_config_set_or_development?).and_return(true) # rubocop:disable RSpec/AnyInstance
  end

  after { Current.reset }

  shared_examples 'a branded email' do
    it 'names the brand and never Chatwoot' do
      expect(body).to include('Acme Desk')
      expect("#{mail.subject} #{body}").not_to match(/chatwoot/i)
    end

    it 'shows the brand in the footer without a link when no brand URL is set' do
      footer = Nokogiri::HTML(body).at_css('.footer')
      expect(footer.text.squish).to eq('This email was sent by Acme Desk.')
      expect(footer.at_css('a')).to be_nil
    end
  end

  describe 'account deletion requested by an admin' do
    let(:mail) { AdministratorNotifications::AccountNotificationMailer.with(account: account).account_deletion_user_initiated(account, 'manual') }

    it_behaves_like 'a branded email'
  end

  describe 'account deletion for inactivity' do
    let(:mail) { AdministratorNotifications::AccountNotificationMailer.with(account: account).account_deletion_for_inactivity(account, 'inactive') }

    it_behaves_like 'a branded email'
  end

  describe 'account deleted (compliance record)' do
    let(:mail) { AdministratorNotifications::AccountComplianceMailer.with(soft_deleted_users: []).account_deleted(account) }

    it_behaves_like 'a branded email'
  end
end
