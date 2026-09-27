# WaDesk: operator console page (CR-004). The installation-wide settings the operator may change (Wadesk::InstallationSettings).
class SuperAdmin::WadeskSettingsController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  SAVED = 'Settings saved. Clients see the change the next time a page loads.'.freeze
  NOT_SAVED = 'Nothing was saved. Fix the highlighted settings and save again.'.freeze

  before_action :set_settings

  def show
    @values = @settings.values
  end

  def update
    @errors = @settings.update(settings_params)
    return redirect_to(super_admin_wadesk_settings_path, notice: SAVED) if @errors.empty?

    @values = @settings.values.merge(settings_params.to_h)
    flash.now[:error] = NOT_SAVED
    render :show, status: :unprocessable_content
  end

  private

  def set_settings
    @settings = Wadesk::InstallationSettings.new
  end

  # Only allow-listed settings pass; anything else (secrets, other installation configs) is dropped here.
  def settings_params
    params.require(:settings).permit(*@settings.editable_keys)
  end
end
