require 'rails_helper'

# WaDesk: installations ship without a brand URL, so the help center footer names the brand without a link.
RSpec.describe 'Public portal brand footer', type: :request do
  let(:portal) { create(:portal, slug: 'brand-portal', custom_domain: 'www.example.com') }
  let(:footer) { Nokogiri::HTML(response.body).at_css('footer') }

  around do |example|
    GlobalConfig.clear_cache
    example.run
    GlobalConfig.clear_cache
  end

  before do
    InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME').update!(value: 'WaDesk')
    InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: brand_url)
  end

  %w[classic documentation].each do |layout|
    context "with the #{layout} layout" do
      before { portal.update!(config: portal.config.merge('layout' => layout)) }

      context 'without a brand URL' do
        let(:brand_url) { '' }

        it 'names the brand without a link' do
          get "/hc/#{portal.slug}/en"

          expect(footer.text).to include('WaDesk')
          expect(footer.css('a').map { |link| link['href'] }).not_to include(a_string_including('utm_campaign'))
        end
      end

      context 'with a brand URL' do
        let(:brand_url) { 'https://wadesk.example' }

        it 'links the brand' do
          get "/hc/#{portal.slug}/en"

          expect(footer.css('a').map { |link| link['href'] }).to include(a_string_starting_with('https://wadesk.example?'))
        end
      end
    end
  end
end
