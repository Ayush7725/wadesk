// WaDesk: pages of a feature that is switched off for the account open a
// "not on your plan" page instead. Only the UI is gated; the API is not.
import { PREMIUM_FEATURES } from 'dashboard/featureFlags';

export const FEATURE_NOT_ON_PLAN_PATH = 'not-on-plan';

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
    flag => !keepsPremiumPaywall(flag, store)
  );
  if (!flags.length) return null;

  const account = await loadAccount(store, accountId);
  // Could not load the account: let the page decide rather than block it.
  if (!account?.id) return null;

  const features = account.features || {};
  return flags.find(flag => !features[flag]) || null;
};
