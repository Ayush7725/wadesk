# WaDesk SAFE-FR-10/11: when a WhatsApp customer's whole message is an opt-out phrase, record a marketing
# opt-out and tell agents with an activity note. Replies to the customer stay allowed; nothing is sent to them.
class Wadesk::Safety::OptOutDetector
  # Whole-message matches only, so "don't stop my order" never counts. Operators can replace the list with
  # WADESK_OPT_OUT_KEYWORDS (comma or newline separated).
  DEFAULT_KEYWORDS = [
    'stop', 'stop all', 'stop messages', 'unsubscribe', 'opt out', 'optout', 'no more messages',
    'band karo', 'band kar do', 'bandh karo', 'bandh kar do', 'mat bhejo', 'msg mat bhejo', 'message mat bhejo',
    'बंद करो', 'बंद कर दो', 'मत भेजो', 'मैसेज मत भेजो'
  ].freeze

  pattr_initialize [:message!]

  def perform
    return unless customer_whatsapp_text? && opt_out_phrase?
    return if Wadesk::ConsentEvent.marketing_state(contact) == :opted_out

    Wadesk::ConsentEvent.create!(account: message.account, contact: contact, kind: :opt_out, source: 'whatsapp_message',
                                 evidence: message.content.truncate(255))
    add_activity_note
  end

  private

  def contact = message.sender

  def customer_whatsapp_text?
    message.incoming? && message.inbox.channel_type == 'Channel::Whatsapp' && message.sender.is_a?(Contact) && message.content.present?
  end

  def opt_out_phrase?
    keywords.include?(normalize(message.content))
  end

  def keywords
    configured = GlobalConfigService.load('WADESK_OPT_OUT_KEYWORDS', nil)
    list = configured.present? ? configured.split(/[,\n]/) : DEFAULT_KEYWORDS
    list.map { |keyword| normalize(keyword) }.compact_blank
  end

  # Case, punctuation, emoji and extra spaces do not matter; letters and combining marks (Devanagari) do.
  def normalize(text)
    text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{L}\p{M}\p{N}]+/, ' ').strip
  end

  def add_activity_note
    message.conversation.messages.create!(
      account: message.account, inbox: message.inbox, message_type: :activity,
      content: I18n.t('wadesk.consent.opted_out_activity', name: contact.name, text: message.content.truncate(60))
    )
  end
end
