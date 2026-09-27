// WaDesk: pages of a feature that is switched off for the account open a
// "not on your plan" page instead. Only the UI is gated; the API is not.
import { FEATURE_FLAGS, PREMIUM_FEATURES } from 'dashboard/featureFlags';

export const FEATURE_NOT_ON_PLAN_PATH = 'not-on-plan';

// The features the operator switches per client. Only these hide in the
// sidebar and open "not on your plan" on community installs; every other flag
// keeps upstream behaviour. Keep in sync with the list the Super Admin
// "WaDesk clients" page offers (Ruby constant on the backend).
export const OPERATOR_FEATURE_FLAGS = [
  FEATURE_FLAGS.CAMPAIGNS,
  FEATURE_FLAGS.WHATSAPP_CAMPAIGNS,
  FEATURE_FLAGS.CANNED_RESPONSES,
  FEATURE_FLAGS.MACROS,
  FEATURE_FLAGS.VOICE_RECORDER,
  FEATURE_FLAGS.HELP_CENTER,
  FEATURE_FLAGS.AUTOMATIONS,
  FEATURE_FLAGS.AGENT_BOTS,
  FEATURE_FLAGS.DELAYED_AUTOMATIONS,
  FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS,
  FEATURE_FLAGS.REPORTS,
  FEATURE_FLAGS.CRM,
  FEATURE_FLAGS.COMPANIES,
  FEATURE_FLAGS.CUSTOM_ATTRIBUTES,
  FEATURE_FLAGS.LABELS,
  FEATURE_FLAGS.AGENT_MANAGEMENT,
  FEATURE_FLAGS.TEAM_MANAGEMENT,
  FEATURE_FLAGS.INBOX_MANAGEMENT,
  FEATURE_FLAGS.INTEGRATIONS,
  FEATURE_FLAGS.DATA_IMPORT,
  FEATURE_FLAGS.CHANNEL_WEBSITE,
  FEATURE_FLAGS.CHANNEL_EMAIL,
  FEATURE_FLAGS.CHANNEL_FACEBOOK,
  FEATURE_FLAGS.CHANNEL_INSTAGRAM,
  FEATURE_FLAGS.CHANNEL_TIKTOK,
];

// Flags of the route and every parent it is nested in.
export const routeFeatureFlags = to => {
  const records = to.matched?.length ? to.matched : [to];
  const flags = records.map(record => record.meta?.featureFlag).filter(Boolean);
  return [...new Set(flags)];
};

// Cloud and enterprise keep upstream behaviour for premium features: their
// pages stay reachable and show their own paywall.
const keepsPremiumPaywall = (flag, store) => {
  if (!PREMIUM_FEATURES.includes(flag)) return false;
  if (store.getters['globalConfig/isACustomBrandedInstance']) return false;
  const isEnterprise = window.chatwootConfig?.isEnterprise === 'true';
  return Boolean(
    store.getters['globalConfig/isOnChatwootCloud'] || isEnterprise
  );
};

const loadAccount = async (store, accountId) => {
  const account = store.getters['accounts/getAccount'](accountId);
  if (account?.id) return account;

  // First page load: the account (and its features) is not in the store yet.
  await store.dispatch('accounts/get', { silent: true, accountId });
  return store.getters['accounts/getAccount'](accountId);
};

// Returns the first flag that blocks `to` for the account, or null.
export const findDisabledRouteFeature = async (to, accountId, store) => {
  const flags = routeFeatureFlags(to).filter(
    flag =>
      OPERATOR_FEATURE_FLAGS.includes(flag) && !keepsPremiumPaywall(flag, store)
  );
  if (!flags.length) return null;

  const account = await loadAccount(store, accountId);
  // Could not load the account: let the page decide rather than block it.
  if (!account?.id) return null;

  const features = account.features || {};
  return flags.find(flag => !features[flag]) || null;
};
