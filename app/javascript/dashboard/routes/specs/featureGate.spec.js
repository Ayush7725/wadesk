// WaDesk: opening a page of a feature that is off for the account (direct URL)
// lands on "not on your plan"; the real routes and the real router guard.
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import store from 'dashboard/store';
import { router, validateAuthenticateRoutePermission } from '../index';
import NotOnPlan from '../dashboard/notOnPlan/Index.vue';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import featureList from '../../../../../config/features.yml';

// What the accounts API returns for an account created with the defaults.
const DEFAULT_FEATURES = Object.fromEntries(
  featureList.map(({ name, enabled }) => [name, enabled])
);

vi.mock('dashboard/store', () => {
  const server = { account: null, fetches: 0 };
  const records = [];
  const findAccount = id => records.find(a => a.id === Number(id)) || {};
  return {
    default: {
      server,
      records,
      getters: {
        isLoggedIn: true,
        getCurrentUser: {
          id: 1,
          account_id: 1,
          accounts: [
            {
              id: 1,
              role: 'administrator',
              permissions: ['administrator'],
              status: 'active',
            },
          ],
        },
        'accounts/getAccount': findAccount,
        'globalConfig/isOnChatwootCloud': false,
        'globalConfig/isACustomBrandedInstance': false,
      },
      // accounts/get: what App.vue and the guard use to load the account.
      dispatch: async action => {
        if (action !== 'accounts/get') return;
        server.fetches += 1;
        records.splice(0, records.length, { ...server.account });
      },
    },
  };
});

const accountWith = overrides => ({
  id: 1,
  name: 'Acme Traders',
  features: { ...DEFAULT_FEATURES, ...overrides },
});

// A fresh page load: nothing in the store until the guard fetches it.
const openAccount = account => {
  store.server.account = account;
  store.server.fetches = 0;
  store.records.splice(0, store.records.length);
};

const visit = async path => {
  await router.push(path);
  return router.currentRoute.value;
};

router.beforeEach((to, _from, next) =>
  validateAuthenticateRoutePermission(to, next)
);

beforeEach(async () => {
  openAccount(accountWith({}));
  await router.push('/app/accounts/1/dashboard');
});

const FEATURE_PAGES = [
  [
    'campaigns',
    '/app/accounts/1/campaigns/live_chat',
    'campaigns_livechat_index',
  ],
  ['reports', '/app/accounts/1/reports/overview', 'account_overview_reports'],
  ['crm', '/app/accounts/1/contacts', 'contacts_dashboard_index'],
  ['crm', '/app/accounts/1/contacts/42', 'contacts_edit'],
  ['help_center', '/app/accounts/1/portals/new', 'portals_new'],
  [
    'automations',
    '/app/accounts/1/settings/automation/list',
    'automation_list',
  ],
  ['labels', '/app/accounts/1/settings/labels/list', 'labels_list'],
  [
    'canned_responses',
    '/app/accounts/1/settings/canned-response/list',
    'canned_list',
  ],
];

describe('feature gate on direct URLs', () => {
  it.each(FEATURE_PAGES)(
    'shows "not on your plan" for %s when it is off (%s)',
    async (flag, path) => {
      // A client with the defaults and one or two features switched off.
      openAccount(accountWith({ [flag]: false, macros: false }));

      const route = await visit(path);

      expect(route.name).toBe('feature_not_on_plan');
      expect(route.path).toBe('/app/accounts/1/not-on-plan');
    }
  );

  it.each(FEATURE_PAGES)(
    'opens the page when %s is on (%s)',
    async (_flag, path, routeName) => {
      openAccount(accountWith({ macros: false }));

      const route = await visit(path);

      expect(route.name).toBe(routeName);
    }
  );

  it('loads the account on a fresh page load before deciding', async () => {
    openAccount(accountWith({ reports: false }));

    const route = await visit('/app/accounts/1/reports/overview');

    expect(store.server.fetches).toBe(1);
    expect(route.name).toBe('feature_not_on_plan');
  });

  it('keeps default-off features off (WhatsApp campaigns)', async () => {
    openAccount(accountWith({}));

    const route = await visit('/app/accounts/1/campaigns/whatsapp');

    expect(route.name).toBe('feature_not_on_plan');
  });

  it('keeps upstream paywalls for premium features on Chatwoot Cloud', async () => {
    store.getters['globalConfig/isOnChatwootCloud'] = true;
    openAccount(accountWith({ help_center: false, campaigns: false }));

    expect((await visit('/app/accounts/1/portals/new')).name).toBe(
      'portals_new'
    );
    expect((await visit('/app/accounts/1/campaigns/live_chat')).name).toBe(
      'feature_not_on_plan'
    );
    store.getters['globalConfig/isOnChatwootCloud'] = false;
  });

  it('leaves pages without a feature flag alone', async () => {
    openAccount(
      accountWith({
        campaigns: false,
        reports: false,
        crm: false,
        labels: false,
      })
    );

    expect((await visit('/app/accounts/1/settings/general')).name).toBe(
      'general_settings_index'
    );
    expect((await visit('/app/accounts/1/dashboard')).name).toBe('home');
    expect(store.server.fetches).toBe(0);
  });
});

describe('not on your plan page', () => {
  it('explains the feature is off and links back to conversations', async () => {
    openAccount(accountWith({ campaigns: false }));
    await visit('/app/accounts/1/campaigns/live_chat');
    const push = vi.spyOn(router, 'push');

    const wrapper = mount(NotOnPlan, {
      global: {
        plugins: [
          router,
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: enSettings },
          }),
        ],
        stubs: {
          NextButton: {
            props: ['label'],
            template: '<button @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
      },
    });

    expect(wrapper.text()).toContain("This feature isn't on your plan");
    expect(wrapper.text()).toContain(
      'Ask your WaDesk account manager to turn it on.'
    );
    await wrapper.find('button').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '1' },
    });
    push.mockRestore();
  });
});
