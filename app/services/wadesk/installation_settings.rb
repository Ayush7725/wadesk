# WaDesk: the installation-wide settings the operator may change from the console (CR-004). Only this allow-list can be
# written. Values are stored the way Chatwoot stores them (InstallationConfig, read through GlobalConfig; saving clears
# GlobalConfig's cache, so the apps pick up a change on their next page load).
class Wadesk::InstallationSettings
  Setting = Struct.new(:key, :label, :hint, :kind, keyword_init: true) do
    def brand? = kind != :boolean
  end

  SIGNUP = Setting.new(key: 'ENABLE_ACCOUNT_SIGNUP', kind: :boolean, label: 'Allow new sign-ups',
                       hint: 'When on, anyone can create a new client account from the sign-up page. When off, only you add clients.')

  BRAND = [
    Setting.new(key: 'INSTALLATION_NAME', kind: :text, label: 'App name',
                hint: 'Shown in browser tabs and the chat widget. Anything but "Chatwoot" also hides Chatwoot\'s help links and upsells ' \
                      'in the client app, and client menus then follow exactly the features you switch on per client.'),
    Setting.new(key: 'BRAND_NAME', kind: :text, label: 'Brand name', hint: 'Shown in emails and under the chat widget ("Powered by …").'),
    Setting.new(key: 'BRAND_URL', kind: :url, label: 'Brand website', hint: 'Where the "Powered by" link in emails goes.'),
    Setting.new(key: 'WIDGET_BRAND_URL', kind: :url, label: 'Chat widget link', hint: 'Where the "Powered by" link under the chat widget goes.'),
    Setting.new(key: 'TERMS_URL', kind: :url, label: 'Terms of service', hint: 'Linked from the sign-up page.'),
    Setting.new(key: 'PRIVACY_URL', kind: :url, label: 'Privacy policy', hint: 'Linked from the sign-up page and the app.'),
    Setting.new(key: 'LOGO', kind: :image, label: 'Logo', hint: 'Shown on the login and sign-up pages and in the app.'),
    Setting.new(key: 'LOGO_DARK', kind: :image, label: 'Logo for dark mode', hint: 'The same places, when dark mode is on.'),
    Setting.new(key: 'LOGO_THUMBNAIL', kind: :image, label: 'Small logo', hint: 'The browser tab icon and the chat widget (square, 512 × 512).')
  ].freeze

  TEXT_MAX_LENGTH = 255

  # Chatwoot resets every brand setting to its own defaults once a day when its enterprise edition is installed on the
  # free plan (Internal::ReconcilePlanConfigService in enterprise/). Offering them there would only be undone overnight.
  def self.branding_editable?
    !(ChatwootApp.enterprise? && ChatwootHub.pricing_plan == 'community')
  end

  def settings
    [SIGNUP, *BRAND]
  end

  def editable
    self.class.branding_editable? ? settings : [SIGNUP]
  end

  def editable_keys
    editable.map(&:key)
  end

  # Current values, as the apps read them.
  def values
    stored = InstallationConfig.where(name: BRAND.map(&:key)).to_h { |config| [config.name, config.value] }
    stored.merge(SIGNUP.key => GlobalConfigService.account_signup_enabled?)
  end

  # Returns { key => error } for invalid values; saves nothing unless everything is valid.
  def update(submitted)
    errors = submitted.to_h.filter_map { |key, value| (error = invalid(setting(key), value)) && [key, error] }.to_h
    return errors if errors.any?

    current = values
    InstallationConfig.transaction do
      submitted.each do |key, value|
        value = cast(setting(key), value)
        save(key, value) unless value == current[key]
      end
    end
    {}
  end

  private

  def setting(key)
    editable.find { |candidate| candidate.key == key } || raise(ArgumentError, "#{key} is not an operator setting")
  end

  def invalid(setting, value)
    value = value.to_s.strip
    return ('must be on or off' unless %w[0 1].include?(value)) if setting.kind == :boolean
    return 'cannot be empty' if value.blank?
    return "must be at most #{TEXT_MAX_LENGTH} characters" if value.length > TEXT_MAX_LENGTH

    invalid_address(setting, value) unless setting.kind == :text
  end

  # Web addresses only (no javascript:, no user:password@); logos may also be a file on this server ("/brand-assets/…").
  def invalid_address(setting, value)
    return if web_address?(value) || (setting.kind == :image && value.match?(%r{\A/[^/\s]\S*\z}))

    setting.kind == :image ? 'must be a web address (https://…) or a path on this server (/…)' : 'must be a web address (https://…)'
  end

  def web_address?(value)
    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def cast(setting, value)
    setting.kind == :boolean ? value == '1' : value.to_s.strip
  end

  # Same storage as Chatwoot's own Super Admin; a missing row is created the way config/installation_config.yml would
  # (brand keys locked, i.e. hidden from Chatwoot's raw installation-config list).
  def save(key, value)
    config = InstallationConfig.find_or_initialize_by(name: key) { |new_config| new_config.locked = key != SIGNUP.key }
    config.value = value
    config.save!
  end
end
