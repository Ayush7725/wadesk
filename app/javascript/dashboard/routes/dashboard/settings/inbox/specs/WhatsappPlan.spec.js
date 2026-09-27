import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Whatsapp from '../channels/Whatsapp.vue';
import ChannelList from '../ChannelList.vue';

// WaDesk: the new-inbox flow only offers the WhatsApp options on the account's plan (whatsapp_official / whatsapp_web).
const plan = vi.hoisted(() => ({ features: {} }));

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ query: {}, name: 'settings_inboxes_page_channel' }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { template: '<p />' },
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: {} }),
}));
vi.mock('dashboard/composables/useAccount', async () => {
  const { computed } = await import('vue');
  return {
    useAccount: () => ({
      accountId: computed(() => 1),
      currentAccount: computed(() => ({ id: 1, features: plan.features })),
      isCloudFeatureEnabled: feature => Boolean(plan.features[feature]),
      isOnChatwootCloud: computed(() => false),
      isMetaInboxCreationDisabled: computed(() => false),
    }),
  };
});

const mountWithPlan = (component, features, stubs) => {
  plan.features = features;
  return mount(component, { global: { mocks: { $t: key => key }, stubs } });
};

const providerTitles = features =>
  mountWithPlan(Whatsapp, features, {
    ChannelSelector: { props: ['title'], template: '<li>{{ title }}</li>' },
    WhatsappAccessRequestDialog: true,
  })
    .findAll('li')
    .map(item => item.text());

const channelKeys = features =>
  mountWithPlan(ChannelList, features, {
    ChannelItem: { props: ['channel'], template: '<li>{{ channel.key }}</li>' },
  })
    .findAll('li')
    .map(item => item.text());

const CLOUD = 'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD';
const TWILIO = 'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO';
const WEB = 'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_WEB';

describe('WhatsApp provider picker', () => {
  it('offers Cloud API and Twilio only to accounts on WhatsApp Official', () => {
    expect(providerTitles({ whatsapp_official: true })).toEqual([
      CLOUD,
      TWILIO,
    ]);
    expect(providerTitles({ whatsapp_web: true })).toEqual([WEB]);
  });

  it('offers every provider to accounts on both plans', () => {
    expect(
      providerTitles({ whatsapp_official: true, whatsapp_web: true })
    ).toEqual([CLOUD, TWILIO, WEB]);
  });
});

describe('Channel list', () => {
  it('hides the WhatsApp cards from accounts on neither plan', () => {
    const keys = channelKeys({ channel_website: true });

    expect(keys).not.toContain('whatsapp');
    expect(keys).not.toContain('whatsapp_call');
    expect(keys).toContain('website');
  });

  it('offers WhatsApp but not WhatsApp Calling (Cloud API) to Web-only accounts', () => {
    const keys = channelKeys({ whatsapp_web: true });

    expect(keys).toContain('whatsapp');
    expect(keys).not.toContain('whatsapp_call');
  });

  it('offers both WhatsApp cards to accounts on WhatsApp Official', () => {
    expect(channelKeys({ whatsapp_official: true })).toEqual(
      expect.arrayContaining(['whatsapp', 'whatsapp_call'])
    );
  });
});
