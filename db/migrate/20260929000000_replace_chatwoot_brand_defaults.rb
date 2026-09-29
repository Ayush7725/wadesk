# WaDesk: config/installation_config.yml now ships WaDesk brand defaults, but ConfigLoader only creates missing rows,
# so existing installations keep Chatwoot's name and links. Move the rows still at Chatwoot's defaults to the new
# defaults; anything the operator changed is left alone.
class ReplaceChatwootBrandDefaults < ActiveRecord::Migration[7.1]
  DEFAULTS = {
    'INSTALLATION_NAME' => %w[Chatwoot WaDesk],
    'BRAND_NAME' => %w[Chatwoot WaDesk],
    'BRAND_URL' => ['https://www.chatwoot.com', ''],
    'WIDGET_BRAND_URL' => ['https://www.chatwoot.com', ''],
    'TERMS_URL' => ['https://www.chatwoot.com/terms-of-service', '/terms.html'],
    'PRIVACY_URL' => ['https://www.chatwoot.com/privacy-policy', '/privacy.html']
  }.freeze

  def up
    DEFAULTS.each do |name, (chatwoot_default, wadesk_default)|
      config = InstallationConfig.find_by(name: name)
      config.update!(value: wadesk_default) if config&.value == chatwoot_default
    end
  end
end
