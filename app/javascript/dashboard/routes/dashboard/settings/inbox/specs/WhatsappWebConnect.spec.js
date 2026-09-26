import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsappWebConnect from '../components/WhatsappWebConnect.vue';

const api = vi.hoisted(() => ({ get: vi.fn(), reconnect: vi.fn() }));

vi.mock('dashboard/api/whatsappWebSession', () => ({ default: api }));
vi.mock('qrcode', () => ({
  default: { toDataURL: vi.fn(async () => 'data:image/png;base64,QR') },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mountConnect = () =>
  mount(WhatsappWebConnect, {
    props: { inboxId: 7 },
    global: {
      mocks: {
        $t: (key, params) =>
          params ? `${key}:${JSON.stringify(params)}` : key,
      },
      stubs: {
        Spinner: true,
        Button: {
          props: ['label', 'isLoading'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('WhatsappWebConnect', () => {
  let wrapper;

  beforeEach(() => {
    vi.useFakeTimers();
    api.get.mockReset();
    api.reconnect.mockReset();
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  it('shows the pairing code with instructions while waiting for the phone', async () => {
    api.get.mockResolvedValue({
      data: {
        state: 'qr_pending',
        pairing_code: 'ABCD1234',
        link_method: 'code',
      },
    });

    wrapper = mountConnect();
    await flushPromises();

    expect(api.get).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-test="pairing-code"]').text()).toBe('ABCD1234');
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.WHATSAPP_WEB.CONNECT.CODE_STEPS'
    );
    expect(wrapper.find('[data-test="state"]').text()).toBe(
      'INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.qr_pending'
    );
  });

  it('draws the QR code', async () => {
    api.get.mockResolvedValue({
      data: { state: 'qr_pending', qr: '2@abc', link_method: 'qr' },
    });

    wrapper = mountConnect();
    await flushPromises();

    expect(wrapper.find('[data-test="qr-code"]').attributes('src')).toBe(
      'data:image/png;base64,QR'
    );
  });

  it('keeps polling while waiting and announces the connection', async () => {
    api.get
      .mockResolvedValueOnce({ data: { state: 'qr_pending', qr: '2@abc' } })
      .mockResolvedValue({
        data: { state: 'connected', me: { phone: '919876543210' } },
      });

    wrapper = mountConnect();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();

    expect(wrapper.emitted('connected')).toEqual([[{ phone: '919876543210' }]]);
    expect(wrapper.find('[data-test="connected"]').text()).toContain(
      '+919876543210'
    );
  });

  it('explains why linking failed and links again on request', async () => {
    api.get.mockResolvedValue({
      data: { state: 'failed', last_error: 'number_mismatch' },
    });
    api.reconnect.mockResolvedValue({ data: { state: 'connecting' } });

    wrapper = mountConnect();
    await flushPromises();
    expect(wrapper.find('[data-test="error"]').text()).toBe(
      'INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.number_mismatch'
    );

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(api.reconnect).toHaveBeenCalledWith(7);
  });

  it('says so when the WhatsApp service cannot be reached', async () => {
    api.get.mockRejectedValue(new Error('502'));

    wrapper = mountConnect();
    await flushPromises();

    expect(wrapper.find('[data-test="error"]').text()).toBe(
      'INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.unavailable'
    );
  });
});
