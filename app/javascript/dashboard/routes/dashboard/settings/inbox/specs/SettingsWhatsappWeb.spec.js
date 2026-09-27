import Settings from '../Settings.vue';
import inboxMixin from 'shared/mixins/inboxMixin';

// WaDesk: the inbox settings page is where admins reach the WhatsApp Web connection panel after creating the inbox.
// Evaluates the page's real computed properties (and the inbox mixin) for a given inbox, so the tab list and provider
// name come from the same logic the browser runs.
const settingsPageFor = inbox => {
  const page = {
    inbox,
    accountId: 1,
    isOnChatwootCloud: false,
    isFeatureEnabledonAccount: () => false,
    $t: key => key,
  };
  const computed = { ...inboxMixin.computed, ...Settings.computed };
  Object.entries(computed).forEach(([name, compute]) => {
    if (name in page) return;
    Object.defineProperty(page, name, { get: () => compute.call(page) });
  });
  return page;
};

const tabKeys = page => page.tabs.map(tab => tab.key);

describe('Inbox settings for WhatsApp Web', () => {
  const whatsappWeb = {
    id: 2,
    channel_type: 'Channel::Whatsapp',
    provider: 'baileys',
  };

  it('offers the Configuration tab, which holds the connection panel', () => {
    expect(tabKeys(settingsPageFor(whatsappWeb))).toContain('configuration');
  });

  it('names WhatsApp Web as the API provider', () => {
    expect(settingsPageFor(whatsappWeb).whatsAppAPIProviderName).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_WEB'
    );
  });

  it('does not show the Cloud API health tab', () => {
    expect(tabKeys(settingsPageFor(whatsappWeb))).not.toContain(
      'whatsapp-health'
    );
  });

  it('keeps the Configuration and health tabs for WhatsApp Cloud inboxes', () => {
    const keys = tabKeys(
      settingsPageFor({ ...whatsappWeb, provider: 'whatsapp_cloud' })
    );

    expect(keys).toEqual(
      expect.arrayContaining(['configuration', 'whatsapp-health'])
    );
  });
});
