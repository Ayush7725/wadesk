# WaDesk: operator console page (CR-004).
class SuperAdmin::WadeskSettingsController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  def show; end
end
