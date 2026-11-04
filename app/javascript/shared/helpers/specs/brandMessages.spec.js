import { createI18n } from 'vue-i18n';
import dashboardMessages from 'dashboard/i18n';
import widgetMessages from 'widget/i18n';
import surveyMessages from 'survey/i18n';
import { brandMessages } from '../brandMessages';

const collectStrings = (value, path, found) => {
  if (typeof value === 'string') found.push([path, value]);
  else if (value && typeof value === 'object') {
    Object.entries(value).forEach(([key, child]) =>
      collectStrings(child, `${path}.${key}`, found)
    );
  }
  return found;
};

// Machine values, plus the sign-up links Signup/Form.vue swaps for TERMS_URL and PRIVACY_URL.
const EXPECTED_LEFTOVERS =
  /window\.chatwootSettings|\{latestChatwootVersion\}|https:\/\/www\.chatwoot\.com\/(terms|privacy-policy)/g;

describe('brandMessages', () => {
  it.each([
    ['dashboard', dashboardMessages],
    ['widget', widgetMessages],
    ['survey', surveyMessages],
  ])('leaves no Chatwoot in any language of the %s app', (_, messages) => {
    const leftovers = collectStrings(
      brandMessages(messages, 'WaDesk', 'desk.example'),
      '',
      []
    ).filter(([, text]) =>
      /chatwoot/i.test(text.replace(EXPECTED_LEFTOVERS, ''))
    );

    expect(leftovers).toEqual([]);
  });

  it('keeps the sign-up links Signup/Form.vue looks for in every language', () => {
    const branded = brandMessages(dashboardMessages, 'WaDesk', 'desk.example');

    Object.entries(branded).forEach(([locale, messages]) => {
      if (!messages.REGISTER?.TERMS_ACCEPT) return;
      expect(messages.REGISTER.TERMS_ACCEPT, locale).toContain(
        'https://www.chatwoot.com/terms'
      );
    });
  });

  it('renders the installation name through vue-i18n, whatever it contains', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: brandMessages(
        {
          en: {
            LOGIN: 'Login to Chatwoot',
            UPDATE: 'Update {latestChatwootVersion} for Chatwoot',
            SCRIPT: 'window.chatwootSettings = {options};',
            ADDRESS: 'app.chatwoot.com/hc/my-portal or chatwoot.help',
            INFLECTED: 'Chatwootiga',
          },
        },
        'A@B {Desk} | $&',
        'desk.example'
      ),
    });
    const { t } = i18n.global;

    expect(t('LOGIN')).toBe('Login to A@B {Desk} | $&');
    expect(t('UPDATE', { latestChatwootVersion: '9.9' })).toBe(
      'Update 9.9 for A@B {Desk} | $&'
    );
    expect(t('SCRIPT', { options: 'x' })).toBe('window.chatwootSettings = x;');
    expect(t('ADDRESS')).toBe('desk.example/hc/my-portal or desk.example');
    expect(t('INFLECTED')).toBe('A@B {Desk} | $&iga');
  });

  it('uses the name from window.globalConfig', () => {
    window.globalConfig = { INSTALLATION_NAME: 'Acme' };

    expect(brandMessages({ en: { A: 'Chatwoot' } }).en.A).toBe('Acme');

    delete window.globalConfig;
  });
});
