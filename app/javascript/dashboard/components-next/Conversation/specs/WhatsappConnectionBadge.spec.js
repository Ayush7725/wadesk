import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import WhatsappConnectionBadge from '../WhatsappConnectionBadge.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const badgeFor = inbox =>
  mount(WhatsappConnectionBadge, { props: { inbox } }).find(
    '[data-test="whatsapp-connection-badge"]'
  );

describe('WhatsappConnectionBadge', () => {
  it('marks WhatsApp Web inboxes', () => {
    expect(
      badgeFor({
        channel_type: 'Channel::Whatsapp',
        provider: 'baileys',
      }).text()
    ).toBe('INBOX_MGMT.WHATSAPP_WEB.BADGE.WEB');
  });

  it.each([
    [
      'WhatsApp Cloud',
      { channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' },
    ],
    ['360dialog', { channel_type: 'Channel::Whatsapp', provider: 'default' }],
    [
      'Twilio WhatsApp',
      { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
    ],
  ])('marks %s inboxes as official', (_name, inbox) => {
    expect(badgeFor(inbox).text()).toBe(
      'INBOX_MGMT.WHATSAPP_WEB.BADGE.OFFICIAL'
    );
  });

  it.each([
    ['website', { channel_type: 'Channel::WebWidget' }],
    ['Twilio SMS', { channel_type: 'Channel::TwilioSms', medium: 'sms' }],
  ])('shows nothing for %s inboxes', (_name, inbox) => {
    expect(badgeFor(inbox).exists()).toBe(false);
  });
});
