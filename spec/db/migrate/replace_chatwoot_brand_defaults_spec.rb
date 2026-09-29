require 'rails_helper'
require Rails.root.join('db/migrate/20260929000000_replace_chatwoot_brand_defaults')

RSpec.describe ReplaceChatwootBrandDefaults do
  let(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  def set(name, value)
    InstallationConfig.find_or_initialize_by(name: name).update!(value: value, locked: true)
  end

  def value(name)
    InstallationConfig.find_by(name: name).value
  end

  around do |example|
    GlobalConfig.clear_cache
    example.run
    GlobalConfig.clear_cache
  end

  it 'moves settings still at Chatwoot defaults to the WaDesk defaults the apps then read' do
    described_class::DEFAULTS.each { |name, (chatwoot_default, _)| set(name, chatwoot_default) }

    migrate

    expect(GlobalConfig.get(*described_class::DEFAULTS.keys)).to eq(
      'INSTALLATION_NAME' => 'WaDesk', 'BRAND_NAME' => 'WaDesk', 'BRAND_URL' => '', 'WIDGET_BRAND_URL' => '',
      'TERMS_URL' => '/terms.html', 'PRIVACY_URL' => '/privacy.html'
    )
  end

  it 'keeps what the operator chose' do
    set('INSTALLATION_NAME', 'Sharma Support')
    set('TERMS_URL', 'https://sharma.example/terms')

    migrate

    expect(value('INSTALLATION_NAME')).to eq('Sharma Support')
    expect(value('TERMS_URL')).to eq('https://sharma.example/terms')
  end

  it 'matches the defaults shipped in config/installation_config.yml' do
    shipped = ConfigLoader.new.general_configs.to_h { |config| [config['name'], config['value']] }

    expect(described_class::DEFAULTS.transform_values(&:last)).to eq(shipped.slice(*described_class::DEFAULTS.keys))
  end

  it 'does nothing on an installation without these rows' do
    InstallationConfig.where(name: described_class::DEFAULTS.keys).delete_all

    expect { migrate }.not_to change(InstallationConfig, :count)
  end
end
