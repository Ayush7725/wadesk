// WaDesk: every locale file names Chatwoot, and those files are upstream's. Swapping the name when messages load covers
// all languages without editing them, so monthly upstream syncs never conflict here.
// Leaves {latestChatwootVersion} alone; covers "Chatwootiga", "ChatWoot" and Chinese text with no space around the name.
const BRAND_WORD = /(?<![a-zA-Z])Chat[Ww]oot/g;
const LOWERCASE_BRAND_WORD = /(?<=\s)chatwoot(?=\s)/g; // a few translations; leaves window.chatwootSettings alone
// Machine translation split this link in a few languages; Signup/Form.vue swaps the exact link.
const BROKEN_PRIVACY_LINK = /chatwoot\.com\/[^"]*\sprivacy-policy/g;
const CHATWOOT_HOSTS = /\b(?:app\.chatwoot\.com|chatwoot\.help)\b/g; // help texts showing the portal address

// The name goes into vue-i18n's message syntax, where these characters mean something.
const escapeForMessage = name =>
  name.replace(/[{}@|]/g, character => `{'${character}'}`);

const brandText = (text, name, host) =>
  text
    .replace(BRAND_WORD, () => name)
    .replace(LOWERCASE_BRAND_WORD, () => name)
    .replace(BROKEN_PRIVACY_LINK, 'chatwoot.com/privacy-policy')
    .replace(CHATWOOT_HOSTS, () => host);

const brandValue = (value, name, host) => {
  if (typeof value === 'string') return brandText(value, name, host);
  if (Array.isArray(value)) return value.map(v => brandValue(v, name, host));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, v]) => [key, brandValue(v, name, host)])
    );
  }
  return value;
};

export const brandMessages = (
  messages,
  installationName = window.globalConfig?.INSTALLATION_NAME || 'WaDesk',
  host = window.location.host
) => brandValue(messages, escapeForMessage(installationName), host);
