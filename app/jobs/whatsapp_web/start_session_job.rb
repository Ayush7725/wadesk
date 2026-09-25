# WaDesk: asks the engine to start (or restart) the WhatsApp Web session for a channel.
# Runs in the background so a briefly unavailable engine never blocks inbox creation; retried on failure.
class WhatsappWeb::StartSessionJob < ApplicationJob
  queue_as :default

  def perform(channel)
    WhatsappWeb::EngineClient.new.upsert_session(channel)
  end
end
