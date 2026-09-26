# WaDesk SAFE-FR-02: caps chats a WhatsApp Web number starts with contacts who never wrote to it.
# Replies to customers who wrote in are never capped. Our own conservative default, not a Meta
# threshold (ADR-0006). The platform operator can change it per account in account.custom_attributes;
# account admins cannot set that key through the API (SAFE-NFR-03).
class Wadesk::Safety::NewChatLimit
  DEFAULT_DAILY_LIMIT = 20
  WINDOW = 24.hours
  LIMIT_KEY = 'wadesk_whatsapp_web_daily_new_chats'.freeze

  pattr_initialize [:message!]

  def exceeded?
    return false if customer_wrote_in?
    return false if chat_already_started?

    started_chats >= daily_limit
  end

  def daily_limit
    message.account.custom_attributes[LIMIT_KEY]&.to_i || DEFAULT_DAILY_LIMIT
  end

  private

  delegate :inbox, :conversation, to: :message

  def customer_wrote_in?
    inbox.messages.incoming.joins(:conversation).exists?(conversations: { contact_id: conversation.contact_id })
  end

  # A chat started earlier in the window already counted; later messages to the same contact are free.
  def chat_already_started?
    recent_outgoing.joins(:conversation).exists?(conversations: { contact_id: conversation.contact_id })
  end

  def started_chats
    recent_outgoing.joins(:conversation)
                   .where.not(conversations: { contact_id: contacts_who_wrote_in })
                   .distinct.count('conversations.contact_id')
  end

  def recent_outgoing
    inbox.messages.outgoing.where(created_at: WINDOW.ago..).where.not(id: message.id).where.not(status: :failed)
  end

  def contacts_who_wrote_in
    inbox.conversations.joins(:messages).merge(Message.incoming).select(:contact_id)
  end
end
