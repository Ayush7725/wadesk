# WaDesk: the Chatwoot features the operator may show or hide per client, from the operator console's client page.
# Single source of truth for the allow-list, the groups, the plain-words descriptions and the warnings shown when a
# feature is turned off. Each name is an existing account feature flag (config/features.yml); the client dashboard
# reads the same flags, so turning one off hides it there. Data is kept, so turning it back on restores it.
module Wadesk::ClientFeatures
  Feature = Data.define(:name, :label, :description, :off_warning)
  Group = Data.define(:title, :features)

  KEEPS_INBOXES = 'Existing inboxes of this type keep working'.freeze

  GROUPS = [
    ['Channels', [
      ['channel_website', 'Website live chat', 'A chat widget on the client\'s website', KEEPS_INBOXES],
      ['channel_email', 'Email inboxes', 'Receive and reply to emails in WaDesk', KEEPS_INBOXES],
      ['channel_facebook', 'Facebook Messenger', 'Messages sent to a Facebook Page', KEEPS_INBOXES],
      ['channel_instagram', 'Instagram', 'Direct messages sent to an Instagram account', KEEPS_INBOXES],
      ['channel_tiktok', 'TikTok', 'Direct messages sent to a TikTok business account', KEEPS_INBOXES]
    ]],
    ['Conversations', [
      ['canned_responses', 'Canned responses', 'Saved replies agents insert with a shortcut', nil],
      ['macros', 'Macros', 'Run a saved set of actions on a conversation in one click', nil],
      ['voice_recorder', 'Voice notes from agents', 'Agents record and send voice messages', nil],
      ['labels', 'Labels settings', 'Create and manage labels for conversations and contacts', nil],
      ['custom_attributes', 'Custom attributes', 'Extra fields on conversations and contacts', nil]
    ]],
    ['Automation', [
      ['automations', 'Automation rules', 'Rules that act on conversations automatically', nil],
      ['agent_bots', 'Agent bots', 'Bots that reply to customers in an inbox', 'Bots already attached to inboxes keep replying'],
      ['delayed_automations', 'Delayed automation steps', 'Wait steps inside automation rules', 'Waiting delayed steps are dropped'],
      ['auto_resolve_conversations', 'Auto-resolve conversations', 'Close conversations after a period with no activity',
       'Auto-resolve already set up keeps running']
    ]],
    ['Engagement', [
      ['campaigns', 'Campaigns', 'Messages to website visitors and contact lists', 'Website pop-up campaigns stop showing'],
      ['whatsapp_campaign', 'WhatsApp campaigns', 'Bulk template messages to contacts. Only for WhatsApp Official inboxes',
       'Scheduled WhatsApp campaigns will not be sent'],
      ['help_center', 'Help center', 'A public site of help articles', nil]
    ]],
    ['Insights & contacts', [
      ['reports', 'Reports', 'Conversation, agent and inbox reports', nil],
      ['crm', 'Contacts', 'The contact list and each contact\'s details', nil],
      ['companies', 'Companies', 'Group contacts by the company they work for', nil]
    ]],
    ['Team & settings', [
      ['agent_management', 'Agents', 'Invite agents and manage their roles', nil],
      ['team_management', 'Teams', 'Group agents into teams', nil],
      ['inbox_management', 'Inboxes', 'Add and set up inboxes', nil],
      ['integrations', 'Integrations', 'Connect other apps such as Slack or webhooks', 'Connected integrations keep working'],
      ['data_import', 'Data import', 'Import contacts from a file', nil]
    ]]
  ].map { |title, features| Group.new(title: title, features: features.map { |attrs| Feature.new(*attrs) }) }.freeze

  BY_NAME = GROUPS.flat_map(&:features).index_by(&:name).freeze
  NAMES = BY_NAME.keys.freeze

  def self.fetch(name)
    BY_NAME.fetch(name.to_s)
  end
end
