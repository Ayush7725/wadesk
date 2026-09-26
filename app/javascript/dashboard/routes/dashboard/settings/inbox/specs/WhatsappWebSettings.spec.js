import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsappWebSettings from '../settingsPage/WhatsappWebSettings.vue';

const api = vi.hoisted(() => ({ reconnect: vi.fn(), logout: vi.fn() }));
const refresh = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/whatsappWebSession', () => ({ default: api }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountSettings = () =>
  mount(WhatsappWebSettings, {
    props: { inbox: { id: 9, provider_config: { link_method: 'qr' } } },
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsFieldSection: { template: '<section><slot /></section>' },
        WhatsappWebConnect: {
          props: ['inboxId'],
          setup: (_props, { expose }) => expose({ refresh }),
          template: '<div data-test="connect" />',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template:
            '<button :data-test="$attrs[\'data-test\']" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('WhatsappWebSettings', () => {
  beforeEach(() => {
    api.reconnect.mockReset();
    api.logout.mockReset();
    refresh.mockReset();
  });

  it('shows the live connection panel for this inbox', () => {
    expect(mountSettings().find('[data-test="connect"]').exists()).toBe(true);
  });

  it('switches to linking with a pairing code', async () => {
    api.reconnect.mockResolvedValue({
      data: { state: 'connecting', link_method: 'code' },
    });
    const wrapper = mountSettings();

    await wrapper.find('[data-test="use-code"]').trigger('click');
    await flushPromises();

    expect(api.reconnect).toHaveBeenCalledWith(9, 'code');
    expect(refresh).toHaveBeenCalled();
  });

  it('asks for confirmation before logging out', async () => {
    api.logout.mockResolvedValue({ data: { state: 'logged_out' } });
    const wrapper = mountSettings();

    await wrapper.find('[data-test="logout"]').trigger('click');
    expect(api.logout).not.toHaveBeenCalled();

    await wrapper.find('[data-test="confirm-logout"]').trigger('click');
    await flushPromises();

    expect(api.logout).toHaveBeenCalledWith(9);
    expect(refresh).toHaveBeenCalled();
  });
});
