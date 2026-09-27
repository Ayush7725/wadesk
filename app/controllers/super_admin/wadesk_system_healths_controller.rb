# WaDesk: operator console page (CR-004). Whether every part of WaDesk is running, in plain words.
class SuperAdmin::WadeskSystemHealthsController < SuperAdmin::ApplicationController
  include SuperAdmin::WadeskConsole

  def show
    @health = Wadesk::SystemHealth.new
  end
end
