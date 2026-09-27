// WaDesk: a feature switched off for the account disappears from the sidebar
// on a community install. Real Sidebar, routes, usePolicy and store getters.
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Sidebar from '../Sidebar.vue';
import { router } from 'dashboard/routes/index';
import { getters as accountGetters } from 'dashboard/store/modules/accounts';
import { getters as globalConfigGetters } from 'shared/store/globalConfig';
import featureList from '../../../../../../config/features.yml';

// The routes' own store import (redirect helpers) is not used here.
vi.mock('dashboard/store', () => ({ default: { getters: {} } }));

// What the accounts API returns for an account created with the defaults.
const DEFAULT_FEATURES = Object.fromEntries(
  featureList.map(({ name, enabled }) => [name, enabled])
);

const noop = () => {};
const staticModule = (getters, actions = []) => ({
  namespaced: true,
  getters,
  actions: Object.fromEntries(actions.map(name => [name, noop])),
});

const buildStore = features =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => 1,
      getCurrentUser: () => ({
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
      }),
      getUserAccounts: () => [],
      getCurrentUserAvailability: () => 'online',
      getCurrentUserAutoOffline: () => false,
      getUISettings: () => ({}),
    },
    actions: { updateUISettings: noop },
    modules: {
      accounts: {
        namespaced: true,
        state: { records: [{ id: 1, name: 'Acme Traders', features }] },
        getters: accountGetters,
      },
      globalConfig: {
        namespaced: true,
        // A community install keeping the default installation name.
        state: { installationName: 'Chatwoot', deploymentEnv: '' },
        getters: globalConfigGetters,
      },
      inboxes: staticModule({ getInboxes: () => [] }, ['get']),
      labels: staticModule({ getLabelsOnSidebar: () => [] }, ['get']),
      teams: staticModule({ getMyTeams: () => [] }, ['get']),
      attributes: staticModule({}, ['get']),
      notifications: staticModule({}, ['unReadCount']),
      customViews: staticModule(
        {
          getContactCustomViews: () => [],
          getConversationCustomViews: () => [],
        },
        ['get']
      ),
      conversationUnreadCounts: staticModule(
        {
          getAllUnreadCount: () => 0,
          getInboxUnreadCount: () => () => 0,
          getLabelUnreadCount: () => () => 0,
          getTeamUnreadCount: () => () => 0,
          getMentionsUnreadCount: () => 0,
          getParticipatingUnreadCount: () => 0,
          getUnattendedUnreadCount: () => 0,
          getFolderUnreadCount: () => () => 0,
        },
        ['get', 'clear']
      ),
      sidebarSortPreferences: staticModule(
        { getSectionSort: () => () => null },
        ['initialize', 'setSectionSort']
      ),
    },
  });

const mountSidebar = async (overrides = {}) => {
  await router.push('/app/accounts/1/dashboard');
  const store = buildStore({ ...DEFAULT_FEATURES, ...overrides });
  const wrapper = mount(Sidebar, {
    global: {
      plugins: [router, store],
      stubs: {
        SidebarProfileMenu: true,
        SidebarAccountSwitcher: true,
        SidebarChangelogCard: true,
        SidebarChangelogButton: true,
        ComposeConversation: true,
        Logo: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const hasLink = (wrapper, path) =>
  wrapper.findAll('a').some(a => a.attributes('href')?.startsWith(path));
const hasGroup = (wrapper, label) =>
  wrapper.find(`[title="${label}"]`).exists();

// [flag, sidebar group or item label, link it points to]
const FEATURE_ITEMS = [
  ['campaigns', 'SIDEBAR.CAMPAIGNS', '/app/accounts/1/campaigns'],
  ['reports', 'SIDEBAR.REPORTS', '/app/accounts/1/reports'],
  ['crm', 'SIDEBAR.CONTACTS', '/app/accounts/1/contacts'],
  ['companies', 'SIDEBAR.COMPANIES', '/app/accounts/1/companies'],
  ['help_center', 'SIDEBAR.HELP_CENTER.TITLE', '/app/accounts/1/portals'],
  ['automations', 'SIDEBAR.AUTOMATION', '/app/accounts/1/settings/automation'],
  ['labels', 'SIDEBAR.LABELS', '/app/accounts/1/settings/labels'],
  ['macros', 'SIDEBAR.MACROS', '/app/accounts/1/settings/macros'],
  [
    'canned_responses',
    'SIDEBAR.CANNED_RESPONSES',
    '/app/accounts/1/settings/canned-response',
  ],
  [
    'custom_attributes',
    'SIDEBAR.CUSTOM_ATTRIBUTES',
    '/app/accounts/1/settings/custom-attributes',
  ],
  ['agent_bots', 'SIDEBAR.AGENT_BOTS', '/app/accounts/1/settings/agent-bots'],
  [
    'integrations',
    'SIDEBAR.INTEGRATIONS',
    '/app/accounts/1/settings/integrations',
  ],
  ['agent_management', 'SIDEBAR.AGENTS', '/app/accounts/1/settings/agents'],
  ['inbox_management', 'SIDEBAR.INBOXES', '/app/accounts/1/settings/inboxes'],
  ['team_management', 'SIDEBAR.TEAMS', '/app/accounts/1/settings/teams'],
];

describe('Sidebar with per-account feature flags (community install)', () => {
  it.each(FEATURE_ITEMS)(
    'hides %s when it is off for the account',
    async (flag, label, path) => {
      // A client with the defaults and one or two features switched off.
      // (WhatsApp campaigns is off by default, so Campaigns goes entirely.)
      const wrapper = await mountSidebar({
        [flag]: false,
        voice_recorder: false,
      });

      expect(hasGroup(wrapper, label)).toBe(false);
      expect(hasLink(wrapper, path)).toBe(false);
    }
  );

  it.each(FEATURE_ITEMS)(
    'shows %s when it is on',
    async (_flag, label, path) => {
      const wrapper = await mountSidebar({ voice_recorder: false });

      expect(hasGroup(wrapper, label)).toBe(true);
      expect(hasLink(wrapper, path)).toBe(true);
    }
  );

  it('keeps Campaigns with only WhatsApp when just WhatsApp campaigns is on', async () => {
    const wrapper = await mountSidebar({
      campaigns: false,
      whatsapp_campaign: true,
    });

    expect(hasGroup(wrapper, 'SIDEBAR.CAMPAIGNS')).toBe(true);
    expect(hasLink(wrapper, '/app/accounts/1/campaigns/whatsapp')).toBe(true);
    expect(hasLink(wrapper, '/app/accounts/1/campaigns/live_chat')).toBe(false);
  });

  it('leaves entries without a feature flag alone', async () => {
    const wrapper = await mountSidebar({
      campaigns: false,
      reports: false,
      crm: false,
      labels: false,
      automations: false,
    });

    expect(hasGroup(wrapper, 'SIDEBAR.CONVERSATIONS')).toBe(true);
    expect(hasLink(wrapper, '/app/accounts/1/dashboard')).toBe(true);
    expect(hasLink(wrapper, '/app/accounts/1/settings/general')).toBe(true);
  });
});
