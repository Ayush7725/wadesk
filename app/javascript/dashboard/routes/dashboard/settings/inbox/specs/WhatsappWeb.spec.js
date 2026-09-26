import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsappWeb from '../channels/WhatsappWeb.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn(), replace: vi.fn() }));

vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mocks.dispatch }) }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const InputStub = {
  props: ['modelValue', 'label', 'message'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /><span class="message">{{ message }}</span></label>',
};

const mountForm = () =>
  mount(WhatsappWeb, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        Input: InputStub,
        RadioCard: {
          props: ['id', 'label'],
          emits: ['select'],
          template:
            '<button type="button" :data-test="\'method-\' + id" @click="$emit(\'select\', id)">{{ label }}</button>',
        },
        Checkbox: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input type="checkbox" data-test="acknowledge" @change="$emit(\'update:modelValue\', $event.target.checked)" />',
        },
        Banner: { template: '<div data-test="warning"><slot /></div>' },
        Button: {
          props: ['label', 'type'],
          emits: ['click'],
          template:
            '<button :type="type || \'button\'" :data-test="$attrs[\'data-test\']" @click="$emit(\'click\')">{{ label }}</button>',
        },
        WhatsappWebConnect: {
          props: ['inboxId'],
          template: '<div data-test="connect">{{ inboxId }}</div>',
        },
      },
    },
  });

const fill = async (wrapper, name, phone) => {
  const inputs = wrapper.findAll('input:not([type="checkbox"])');
  await inputs[0].setValue(name);
  await inputs[1].setValue(phone);
};

describe('WhatsappWeb', () => {
  beforeEach(() => {
    mocks.dispatch.mockReset();
    mocks.replace.mockReset();
  });

  it('warns that WhatsApp Web is unofficial', () => {
    expect(mountForm().find('[data-test="warning"]').text()).toBe(
      'INBOX_MGMT.WHATSAPP_WEB.FORM.WARNING'
    );
  });

  it('requires the risk acknowledgement before creating the inbox', async () => {
    const wrapper = mountForm();
    await fill(wrapper, 'Sales', '+919876543210');

    await wrapper.find('form').trigger('submit');

    expect(wrapper.find('[data-test="acknowledge-error"]').exists()).toBe(true);
    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('rejects numbers without a country code', async () => {
    const wrapper = mountForm();
    await fill(wrapper, 'Sales', '9876543210');
    await wrapper.find('[data-test="acknowledge"]').setValue(true);

    await wrapper.find('form').trigger('submit');

    expect(wrapper.text()).toContain(
      'INBOX_MGMT.WHATSAPP_WEB.FORM.PHONE_NUMBER.ERROR'
    );
    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('creates a WhatsApp Web inbox with the chosen link method, then shows the linking panel', async () => {
    mocks.dispatch.mockResolvedValue({ id: 42 });
    const wrapper = mountForm();
    await fill(wrapper, ' Sales ', '+919876543210');
    await wrapper.find('[data-test="method-code"]').trigger('click');
    await wrapper.find('[data-test="acknowledge"]').setValue(true);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('inboxes/createChannel', {
      name: 'Sales',
      channel: {
        type: 'whatsapp',
        phone_number: '+919876543210',
        provider: 'baileys',
        provider_config: { link_method: 'code' },
      },
    });
    expect(wrapper.find('[data-test="connect"]').text()).toBe('42');
  });
});
