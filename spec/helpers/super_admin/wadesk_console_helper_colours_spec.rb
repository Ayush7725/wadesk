require 'rails_helper'

# WaDesk: the operator console uses the client dashboard's colour tokens (n-*). Super Admin loads its own stylesheet;
# a class whose CSS variable is missing there renders transparent without any error (e.g. the Official badge, #51).
RSpec.describe SuperAdmin::WadeskConsoleHelper do
  let(:stylesheet) { Rails.root.join('app/javascript/dashboard/assets/scss/super_admin/index.scss').read }
  let(:tokens) { Rails.root.join('app/javascript/dashboard/assets/scss/_next-colors.scss').read }
  let(:console_views) do
    pages = 'super_admin/{wadesk_console,wadesk_overview,wadesk_clients,whatsapp_web_numbers}/**/*'
    Rails.root.glob("app/views/{layouts/super_admin/wadesk_console,#{pages}}.html.erb") +
      [Rails.root.join('app/helpers/super_admin/wadesk_console_helper.rb')]
  end

  it 'loads the dashboard colour tokens in Super Admin, so the console\'s colours render' do
    expect(stylesheet).to include("@import 'dashboard/assets/scss/next-colors';")
  end

  it 'only uses colour scales that are defined in light and dark' do
    scales = console_views.flat_map { |file| file.read.scan(/-n-(slate|blue|teal|ruby|amber|iris|gray|violet)-(\d+)\b/) }.uniq
    light, dark = tokens.split(/^\s*\.dark\s*\{/, 2)

    missing = scales.reject { |name, step| light.include?("--#{name}-#{step}:") && dark.include?("--#{name}-#{step}:") }
    expect(scales).not_to be_empty
    expect(missing).to be_empty, "Missing colour tokens: #{missing.map { |name, step| "--#{name}-#{step}" }.join(', ')}"
  end
end
