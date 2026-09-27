# WaDesk: operator console page (CR-004).
class SuperAdmin::WadeskUsersController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  def index; end
end
