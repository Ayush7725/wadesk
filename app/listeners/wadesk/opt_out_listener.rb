# WaDesk: checks new customer messages for opt-out phrases (SAFE-FR-10).
class Wadesk::OptOutListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    Wadesk::Safety::OptOutDetector.new(message: message).perform
  end
end
