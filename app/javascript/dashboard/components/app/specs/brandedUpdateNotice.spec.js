import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { computed } from 'vue';
import UpdateBanner from '../UpdateBanner.vue';
import BuildInfo from 'dashboard/routes/dashboard/settings/account/components/BuildInfo.vue';

// WaDesk: Chatwoot's "new version available" notices mean nothing to our clients, who get updates from us.
const brand = vi.hoisted(() => ({ custom: true }));
const config = {
  appVersion: '1.0.0',
  displayManifest: true,
  gitSha: 'abcdef1234',
};

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: computed(() => ({ latest_chatwoot_version: '9.9.9' })),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    computed(() => (name === 'globalConfig/get' ? config : brand.custom)),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const NOTICE = 'GENERAL_SETTINGS.UPDATE_CHATWOOT';
const store = () =>
  createStore({
    getters: {
      'globalConfig/get': () => config,
      'globalConfig/isACustomBrandedInstance': () => brand.custom,
    },
  });

const banner = () =>
  mount(UpdateBanner, {
    props: { latestChatwootVersion: '9.9.9' },
    global: {
      plugins: [store()],
      mocks: { $t: key => key },
      stubs: {
        Banner: {
          props: ['bannerMessage'],
          template: '<p>{{ bannerMessage }}</p>',
        },
      },
    },
  });
const buildInfo = () =>
  mount(BuildInfo, { global: { directives: { tooltip: {} } } });

describe('update notices', () => {
  it.each([
    ['the update banner', banner],
    ['the account build info', buildInfo],
  ])('are hidden in %s on a branded installation', (_, render) => {
    brand.custom = true;
    expect(render().text()).not.toContain(NOTICE);

    brand.custom = false;
    expect(render().text()).toContain(NOTICE);
  });
});
